// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StableERC4626For4626} from "contracts/v2/tokens/StableERC4626For4626.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {MockStableERC4626} from "contracts/v2/test/MockStableERC4626.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC4626TokenEvents} from "contracts/v2/events/ERC4626TokenEvents.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract StableERC4626For4626Test is Test {
    StableERC4626For4626 public stable4626;
    MockERC4626 public thirdPool;
    MockERC20 public underlying;
    address public admin = vm.randomAddress();

    // Events to test
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        underlying = new MockERC20("USDC", "USDC", 6);
        thirdPool = new MockERC4626(underlying);

        vm.label(address(underlying), "USDC");
        vm.label(address(thirdPool), "ThirdPool");
        vm.label(admin, "Admin");

        address implementation = address(new StableERC4626For4626());
        stable4626 = StableERC4626For4626(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        StableERC4626For4626.initialize.selector,
                        admin,
                        address(thirdPool),
                        StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
                    )
                )
            )
        );

        vm.label(address(stable4626), "tmseUSDC");
    }

    function testInitialization() public {
        assertEq(address(stable4626.thirdPool()), address(thirdPool));
        assertEq(address(stable4626.underlying()), address(underlying));
        assertEq(stable4626.owner(), admin);
        assertEq(stable4626.asset(), address(underlying));
        assertEq(stable4626.name(), "TermMax Stable ERC4626 USDC");
        assertEq(stable4626.symbol(), "tmseUSDC");

        // Check buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = stable4626.bufferConfig();
        assertEq(minimumBuffer, 1000e6);
        assertEq(maximumBuffer, 10000e6);
        assertEq(buffer, 5000e6);
    }

    function testMint() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);

        stable4626.deposit(amount, address(this));

        assertEq(stable4626.balanceOf(address(this)), amount);
        assertEq(underlying.balanceOf(address(this)), 0);
        // Check that tokens were deposited to the buffer/third pool
        assertGt(underlying.balanceOf(address(stable4626)) + thirdPool.balanceOf(address(stable4626)), 0);
    }

    function testBurn() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        stable4626.redeem(amount, address(this), address(this));

        assertEq(stable4626.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(this)), amount);
    }

    function testWithdrawIncomeAssets() public {
        // Setup - mint some tokens
        uint256 amount = 20000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // Simulate yield by directly minting tokens to the third pool
        uint256 yieldAmount = 100e6;
        underlying.mint(address(thirdPool), yieldAmount);

        assertEq(stable4626.totalIncomeAssets(), yieldAmount - 1);

        // Withdraw income as the admin
        vm.startPrank(admin);
        stable4626.withdrawIncomeAssets(address(underlying), admin, yieldAmount - 1);
        vm.stopPrank();

        // Assert balances are correct
        assertEq(underlying.balanceOf(admin), yieldAmount - 1);
    }

    function testUpdateBufferConfigAndAddReserves() public {
        uint256 additionalReserves = 500e6;
        underlying.mint(admin, additionalReserves);

        vm.startPrank(admin);
        underlying.approve(address(stable4626), additionalReserves);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        stable4626.updateBufferConfigAndAddReserves(additionalReserves, newConfig);
        vm.stopPrank();

        // Get current buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = stable4626.bufferConfig();

        // Assert the new config was set correctly
        assertEq(minimumBuffer, newConfig.minimumBuffer);
        assertEq(maximumBuffer, newConfig.maximumBuffer);
        assertEq(buffer, newConfig.buffer);

        // Assert the additional reserves were added
        assertEq(underlying.balanceOf(address(stable4626)), additionalReserves);
    }

    function testTotalIncomeAssets() public {
        uint256 amount = 20000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // Simulate yield by directly minting tokens to the third pool
        uint256 yieldAmount = 100e6;
        underlying.mint(address(thirdPool), yieldAmount);

        assertEq(stable4626.totalIncomeAssets(), yieldAmount - 1);
    }

    function testMintZeroAmount() public {
        underlying.mint(address(this), 0);
        underlying.approve(address(stable4626), 0);

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

        // Simulate yield by directly minting tokens to the third pool
        uint256 yieldAmount = 100e6;
        underlying.mint(address(thirdPool), yieldAmount);

        // Try to withdraw more than available income
        vm.startPrank(admin);
        vm.expectRevert();
        stable4626.withdrawIncomeAssets(address(underlying), admin, yieldAmount + 1);
        vm.stopPrank();
    }

    function testNonAdminCannotWithdrawIncome() public {
        // Setup - mint some tokens
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // Simulate yield by directly minting tokens to the third pool
        uint256 yieldAmount = 100e6;
        underlying.mint(address(thirdPool), yieldAmount);

        // Try to withdraw as non-admin
        vm.expectRevert();
        stable4626.withdrawIncomeAssets(address(underlying), address(this), yieldAmount);
    }

    function testNonAdminCannotUpdateBufferConfig() public {
        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        vm.expectRevert();
        stable4626.updateBufferConfigAndAddReserves(0, newConfig);
    }

    function testWithdrawIncomeAsThirdPoolShares() public {
        // Setup - mint some tokens
        uint256 amount = 20000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // Simulate yield by directly minting tokens to the third pool
        uint256 yieldAmount = 100e6;
        underlying.mint(address(thirdPool), yieldAmount);

        // Withdraw income as third pool shares
        vm.startPrank(admin);
        stable4626.withdrawIncomeAssets(address(thirdPool), admin, yieldAmount - 1);
        vm.stopPrank();
    }

    function testWithdrawIncomeAsInvalidToken() public {
        // Setup
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);

        // Attempt to withdraw income with invalid token
        vm.startPrank(admin);
        vm.expectRevert();
        stable4626.withdrawIncomeAssets(address(invalidToken), admin, 100e6);
        vm.stopPrank();
    }

    function testInvalidBufferConfiguration() public {
        vm.startPrank(admin);

        // Test minimum buffer greater than maximum buffer
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

    function testUnauthorizedAccess() public {
        address unauthorizedUser = vm.randomAddress();

        // Test unauthorized buffer config update
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        stable4626.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6})
        );
        vm.stopPrank();

        // Test unauthorized income withdrawal
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        stable4626.withdrawIncomeAssets(address(underlying), unauthorizedUser, 100e6);
        vm.stopPrank();
    }

    function testMintWithInsufficientApproval() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount - 1); // Insufficient approval

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(stable4626), amount - 1, amount
            )
        );
        stable4626.deposit(amount, address(this));
    }

    function testWithdrawIncomeToZeroAddress() public {
        uint256 amount = 20000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        uint256 yieldAmount = 100e6;
        underlying.mint(address(thirdPool), yieldAmount);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        stable4626.withdrawIncomeAssets(address(underlying), address(0), yieldAmount - 1);
        vm.stopPrank();
    }

    function testMintToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        stable4626.deposit(amount, address(0));
    }

    function testBurnToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        stable4626.redeem(amount, address(0), address(this));
    }

    function testUpdateBufferWithInsufficientBalance() public {
        uint256 additionalReserves = 500e6;
        // Don't mint tokens to admin

        vm.startPrank(admin);
        underlying.approve(address(stable4626), additionalReserves);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, admin, 0, additionalReserves)
        );
        stable4626.updateBufferConfigAndAddReserves(additionalReserves, newConfig);
        vm.stopPrank();
    }

    function testConversionFunctions() public {
        uint256 assets = 1000e6;
        uint256 shares = stable4626.convertToShares(assets);
        uint256 convertedAssets = stable4626.convertToAssets(shares);

        // For stable 4626, conversion should be 1:1
        assertEq(shares, assets);
        assertEq(convertedAssets, assets);
    }

    function testTotalAssets() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);
        stable4626.deposit(amount, address(this));

        // For stable 4626, total assets should equal total supply
        assertEq(stable4626.totalAssets(), stable4626.totalSupply());
        assertEq(stable4626.totalAssets(), amount);
    }

    function testEventEmissions() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stable4626), amount);

        // Test deposit event
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amount, amount);
        stable4626.deposit(amount, address(this));

        // Test withdraw event
        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), address(this), address(this), amount, amount);
        stable4626.redeem(amount, address(this), address(this));
    }

    function testFuzzDepositsAndWithdrawals() public {
        vm.startPrank(admin);
        stable4626.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 500e6, maximumBuffer: 1000e6, buffer: 700e6})
        );
        vm.stopPrank();

        address[] memory accounts = new address[](5);
        for (uint256 i = 0; i < accounts.length; i++) {
            accounts[i] = vm.addr(i + 1);
        }

        uint256 totalYield = 0;

        for (uint256 i = 0; i < 100; i++) {
            uint256 amount = vm.randomUint(1e6, 100000e6);
            address account = accounts[vm.randomUint(0, accounts.length - 1)];
            vm.startPrank(account);

            uint256 action = vm.randomUint(0, 1); // 0 for deposit, 1 for redeem
            uint256 underlyingBalanceBefore = underlying.balanceOf(account);
            uint256 shareBalanceBefore = stable4626.balanceOf(account);

            if (action == 0 || shareBalanceBefore < amount) {
                // Deposit action
                if (underlyingBalanceBefore < amount) {
                    underlying.mint(account, amount - underlyingBalanceBefore);
                }
                underlying.mint(account, amount);
                underlying.approve(address(stable4626), amount);
                stable4626.deposit(amount, account);
                assertEq(stable4626.balanceOf(account), amount + shareBalanceBefore);
            } else {
                // Redeem action
                if (stable4626.balanceOf(account) >= amount) {
                    stable4626.redeem(amount, account, account);
                    assertEq(stable4626.balanceOf(account), shareBalanceBefore - amount);
                    assertEq(underlying.balanceOf(account), underlyingBalanceBefore + amount);
                }
            }

            // Simulate yield accumulation
            if (i % 10 == 0) {
                uint256 yield = vm.randomUint(1e6, 50e6);
                underlying.mint(address(thirdPool), yield);
                totalYield += yield;
            }

            vm.stopPrank();
        }
        // there may be some rounding errors, so we allow a small delta
        assertEq(stable4626.totalIncomeAssets(), totalYield - 1);
    }

    function testPreviewFunctions() public {
        uint256 assets = 1000e6;

        // Preview deposits
        uint256 previewShares = stable4626.previewDeposit(assets);
        assertEq(previewShares, assets); // 1:1 conversion for stable

        uint256 previewAssets = stable4626.previewMint(assets);
        assertEq(previewAssets, assets); // 1:1 conversion for stable

        // Deposit some tokens first
        underlying.mint(address(this), assets);
        underlying.approve(address(stable4626), assets);
        stable4626.deposit(assets, address(this));

        // Preview withdrawals
        uint256 previewSharesForWithdraw = stable4626.previewWithdraw(assets);
        assertEq(previewSharesForWithdraw, assets); // 1:1 conversion for stable

        uint256 previewAssetsForRedeem = stable4626.previewRedeem(assets);
        assertEq(previewAssetsForRedeem, assets); // 1:1 conversion for stable
    }

    function testMaxFunctions() public {
        uint256 assets = 1000e6;
        underlying.mint(address(this), assets);
        underlying.approve(address(stable4626), assets);
        stable4626.deposit(assets, address(this));

        // Max functions should return appropriate values
        assertGt(stable4626.maxDeposit(address(this)), 0);
        assertGt(stable4626.maxMint(address(this)), 0);
        assertEq(stable4626.maxWithdraw(address(this)), assets);
        assertEq(stable4626.maxRedeem(address(this)), assets);
    }
}
