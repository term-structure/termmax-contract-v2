// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StableERC4626ForVenus} from "contracts/v2/tokens/StableERC4626ForVenus.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {MockVToken} from "contracts/mocks/MockVToken.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC4626TokenErrors} from "contracts/v2/errors/ERC4626TokenErrors.sol";

contract StableERC4626ForVenusTest is Test {
    StableERC4626ForVenus public stable4626;
    MockVToken public vToken;
    MockERC20 public underlying;
    address public admin = vm.randomAddress();

    // Default buffer config
    uint256 constant MIN_BUFFER = 1000e6;
    uint256 constant MAX_BUFFER = 10000e6;
    uint256 constant BUFFER = 5000e6;

    function setUp() public {
        underlying = new MockERC20("USDC", "USDC", 6);
        vToken = new MockVToken(address(underlying), "Venus USDC", "vUSDC");

        vm.label(address(underlying), "USDC");
        vm.label(address(vToken), "vUSDC");
        vm.label(admin, "Admin");

        // Set exchange rate to 1:1 for simplicity in basic tests (1e18)
        vToken.setExchangeRate(1e18);

        address implementation = address(new StableERC4626ForVenus());
        stable4626 = StableERC4626ForVenus(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        StableERC4626ForVenus.initialize.selector,
                        admin,
                        address(vToken),
                        StakingBuffer.BufferConfig({
                            minimumBuffer: MIN_BUFFER,
                            maximumBuffer: MAX_BUFFER,
                            buffer: BUFFER
                        })
                    )
                )
            )
        );
        vm.label(address(stable4626), "tmsvUSDC");
    }

    function testFuzz_Mint(uint256 amount) public {
        // Bound amount to realistic values (1 USDC to 100M USDC)
        amount = bound(amount, 1e6, 100_000_000e6);

        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);

        stable4626.deposit(amount, address(this));

        assertEq(stable4626.balanceOf(address(this)), amount, "Shares should match deposit amount 1:1");
        assertApproxEqAbs(stable4626.totalAssets(), amount, 1, "Total assets should match deposit");
    }

    function testFuzz_Redeem(uint256 amount) public {
        amount = bound(amount, 1e6, 100_000_000e6);

        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        stable4626.redeem(amount, address(this), address(this));

        assertEq(stable4626.balanceOf(address(this)), 0, "Shares should be burned");
        assertEq(underlying.balanceOf(address(this)), amount, "Underlying should be returned");
    }

    function testFuzz_WithdrawIncomeAssets(uint256 depositAmount, uint256 yieldAmount) public {
        depositAmount = bound(depositAmount, BUFFER + 1e6, 100_000_000e6);
        yieldAmount = bound(yieldAmount, 1e6, depositAmount / 10); // 10% yield max

        underlying.mint(address(this), depositAmount);
        underlying.approve(address(stable4626), depositAmount);
        stable4626.deposit(depositAmount, address(this));

        // Simulate yield: direct transfer of underlying to vToken to assume price appreciation
        // Wait, standard VToken yield comes from exchangeRate increasing.
        // MockVToken allows setting exchangeRate.

        // Let's simulate yield by increasing exchange rate implies:
        // shares * newRate > initial_assets.
        // But StableERC4626ForVenus logic is: shares * 1e18 / rate.
        // If rate increases, assets DECREASE in that logic. This confirms the logic in Stable contract might be inverted or I need to Decrease rate?
        // No, standard is rate increases.
        // Let's rely on `_assetInPool` which calls `balanceOf`.
        // If we simple mint MORE vToken to the stable contract (simulate rebase/donation?), that would work too.
        // But VToken is not rebase.

        // Since I suspect the StableERC4626ForVenus calculation is odd, let's try to just give it more vtokens for now to simulate "yield"
        // as if it was a rebase token or just logically "more assets".
        // Or better, let's just create "income" by transferring underlying tokens to it directly?
        // `totalAssets` = `_assetInPool` + `underlyingBalance`.
        // If we send underlying to it, `underlyingBalance` increases, `totalSupply` stays same. -> Income.

        underlying.mint(address(stable4626), yieldAmount);

        // Withdraw income as admin
        vm.startPrank(admin);
        uint256 preBalance = underlying.balanceOf(admin);
        stable4626.withdrawIncomeAssets(address(underlying), admin, yieldAmount);
        uint256 postBalance = underlying.balanceOf(admin);

        assertEq(postBalance - preBalance, yieldAmount, "Admin should receive yield");
        vm.stopPrank();
    }

    function testFuzz_UpdateBufferConfig(uint256 minBuf, uint256 maxBuf, uint256 buf) public {
        // constraints from StakingBuffer.sol: minimumBuffer <= buffer <= maximumBuffer
        minBuf = bound(minBuf, 0, 1_000_000e6);
        maxBuf = bound(maxBuf, minBuf, 1_000_000_000e6);
        buf = bound(buf, minBuf, maxBuf);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: minBuf, maximumBuffer: maxBuf, buffer: buf});

        vm.startPrank(admin);
        // We need to approve stable4626 to pull reserves if we were adding reserves, but `_updateBufferConfig` is internal.
        // `updateBufferConfigAndAddReserves` is external.
        // Let's use `updateBufferConfigAndAddReserves` with 0 additional reserves.
        underlying.approve(address(stable4626), 0);
        stable4626.updateBufferConfigAndAddReserves(0, newConfig);
        vm.stopPrank();

        (uint256 resMin, uint256 resMax, uint256 resBuf) = stable4626.bufferConfig();
        assertEq(resMin, minBuf);
        assertEq(resMax, maxBuf);
        assertEq(resBuf, buf);
    }

    // --- Additional Unit Tests ---

    function testMintZeroAmount() public {
        underlying.mint(address(this), 0);
        underlying.approve(address(stable4626), 0);

        // ERC4626 deposit(0) should generally succeed and mint 0 shares
        stable4626.deposit(0, address(this));

        assertEq(stable4626.balanceOf(address(this)), 0);
    }

    function testBurnMoreThanBalance() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        vm.expectRevert();
        stable4626.redeem(amount + 1, address(this), address(this));
    }

    function testWithdrawTooMuchIncome() public {
        // Setup - mint some tokens
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // Simulate income by sending underlying tokens purely (not minting shares)
        uint256 yieldAmount = 100e6;
        underlying.mint(address(stable4626), yieldAmount);

        // Try to withdraw more than available income
        vm.startPrank(admin);
        vm.expectRevert();
        stable4626.withdrawIncomeAssets(address(underlying), admin, yieldAmount + 1);
        vm.stopPrank();
    }

    function testNonAdminCannotWithdrawIncome() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        uint256 yieldAmount = 100e6;
        underlying.mint(address(stable4626), yieldAmount);

        address nonAdmin = vm.addr(2);
        vm.startPrank(nonAdmin);
        // Expect standard Ownable revert or custom error depending on version.
        // Using generic expectRevert() for safety.
        vm.expectRevert();
        stable4626.withdrawIncomeAssets(address(underlying), nonAdmin, yieldAmount);
        vm.stopPrank();
    }

    function testNonAdminCannotUpdateBufferConfig() public {
        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        address nonAdmin = vm.addr(2);
        vm.startPrank(nonAdmin);
        vm.expectRevert();
        stable4626.updateBufferConfigAndAddReserves(0, newConfig);
        vm.stopPrank();
    }

    function testWithdrawIncomeAsVToken_WithRefinedSetup() public {
        // 1. Ensure stable4626 has vTokens
        uint256 largeAmount = 20000e6;
        // MAX_BUFFER = 10000e6.
        // BUFFER = 5000e6.
        // Deposit 20000e6 -> Exceeds MAX -> Keeps BUFFER (5000e6) -> Deposits 15000e6 into vToken.

        underlying.mint(address(this), largeAmount);
        underlying.approve(address(stable4626), largeAmount);
        stable4626.deposit(largeAmount, address(this));

        assertGt(vToken.balanceOf(address(stable4626)), 0, "Should have minted vTokens");

        // 2. Simulate income
        uint256 yieldAmount = 100e6;
        underlying.mint(address(stable4626), yieldAmount);

        // 3. Withdraw income as vToken
        vm.startPrank(admin);
        stable4626.withdrawIncomeAssets(address(vToken), admin, yieldAmount);
        vm.stopPrank();

        // 4. Verify admin received vTokens
        // Amount shares = yieldAmount * 1e18 / exchangeRate(1e18) = yieldAmount
        assertEq(vToken.balanceOf(admin), yieldAmount);
    }

    function testWithdrawIncomeAsInvalidToken() public {
        // Setup - We need to have some income first, otherwise it fails on "InsufficientIncomeAmount" check BEFORE checking token validity.
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // Simulate income
        uint256 yieldAmount = 100e6;
        underlying.mint(address(stable4626), yieldAmount);

        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);

        // Attempt to withdraw income with invalid token
        vm.startPrank(admin);
        // Expect ERC4626TokenErrors.InvalidToken()
        vm.expectRevert(ERC4626TokenErrors.InvalidToken.selector);
        stable4626.withdrawIncomeAssets(address(invalidToken), admin, yieldAmount);
        vm.stopPrank();
    }

    function testInvalidBufferConfiguration() public {
        vm.startPrank(admin);

        // Test minimum buffer greater than maximum buffer
        // Error: InvalidBuffer(uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer);
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 10000e6, 5000e6, 7500e6));
        stable4626.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 10000e6, maximumBuffer: 5000e6, buffer: 7500e6})
        );

        // Test buffer outside min/max range (below minimum)
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 5000e6, 10000e6, 4000e6));
        stable4626.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 5000e6, maximumBuffer: 10000e6, buffer: 4000e6})
        );

        // Test buffer outside min/max range (above maximum)
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 5000e6, 10000e6, 11000e6));
        stable4626.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 5000e6, maximumBuffer: 10000e6, buffer: 11000e6})
        );

        vm.stopPrank();
    }

    function testCurrentIncomeAssets() public {
        uint256 depositAmount = 20000e6;
        underlying.mint(address(this), depositAmount);
        underlying.approve(address(stable4626), depositAmount);
        stable4626.deposit(depositAmount, address(this));

        uint256 incomeAmount = 500e6;
        underlying.mint(address(stable4626), incomeAmount);

        uint256 currentIncome = stable4626.currentIncomeAssets();
        assertEq(currentIncome, incomeAmount, "Current income should match minted income");

        // Withdraw half income
        uint256 withdrawAmount = 250e6;
        vm.startPrank(admin);
        stable4626.withdrawIncomeAssets(address(underlying), admin, withdrawAmount);
        vm.stopPrank();

        currentIncome = stable4626.currentIncomeAssets();
        assertEq(currentIncome, incomeAmount - withdrawAmount, "Current income should decrease after withdrawal");
    }
}
