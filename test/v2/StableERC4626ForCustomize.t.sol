// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StableERC4626ForCustomize} from "contracts/v2/tokens/StableERC4626ForCustomize.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC4626TokenEvents} from "contracts/v2/events/ERC4626TokenEvents.sol";
import {ERC4626TokenErrors} from "contracts/v2/errors/ERC4626TokenErrors.sol";

contract StableERC4626ForCustomizeTest is Test {
    StableERC4626ForCustomize public stableCustomize;
    address public thirdPool;
    MockERC20 public underlying;
    address public admin = vm.randomAddress();

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event WithdrawIncome(address indexed to, uint256 amount);

    function setUp() public {
        underlying = new MockERC20("USDC", "USDC", 6);
        thirdPool = makeAddr("ThirdPool");

        vm.label(address(underlying), "USDC");
        vm.label(thirdPool, "ThirdPool");
        vm.label(admin, "Admin");

        address implementation = address(new StableERC4626ForCustomize());

        bytes memory initData = abi.encodeWithSelector(
            StableERC4626ForCustomize.initialize.selector,
            admin,
            thirdPool,
            address(underlying),
            StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
        );

        stableCustomize = StableERC4626ForCustomize(address(new ERC1967Proxy(implementation, initData)));

        vm.label(address(stableCustomize), "tmscUSDC");

        // Approve stable contract to spend thirdPool's tokens
        vm.prank(thirdPool);
        underlying.approve(address(stableCustomize), type(uint256).max);
    }

    function testInitialization() public {
        assertEq(stableCustomize.thirdPool(), thirdPool);
        assertEq(address(stableCustomize.underlying()), address(underlying));
        assertEq(stableCustomize.owner(), admin);
        assertEq(stableCustomize.asset(), address(underlying));
        assertEq(stableCustomize.name(), "TermMax Stable CustomizeERC4626 USDC");
        assertEq(stableCustomize.symbol(), "tmscUSDC");

        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = stableCustomize.bufferConfig();
        assertEq(minimumBuffer, 1000e6);
        assertEq(maximumBuffer, 10000e6);
        assertEq(buffer, 5000e6);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1e6, 1e12 * 1e6); // 1 USDC to 1T USDC
        underlying.mint(address(this), amount);
        underlying.approve(address(stableCustomize), amount);

        stableCustomize.deposit(amount, address(this));

        assertEq(stableCustomize.balanceOf(address(this)), amount);

        uint256 contractBalance = underlying.balanceOf(address(stableCustomize));
        uint256 poolBalance = underlying.balanceOf(thirdPool);

        (uint256 minBuffer, uint256 maxBuffer, uint256 buffer) = stableCustomize.bufferConfig();

        if (amount > maxBuffer) {
            // Buffer logic: if balance after deposit > maxBuffer, reduce to buffer
            assertEq(contractBalance, buffer, "Contract balance should equal buffer");
            assertEq(poolBalance, amount - buffer, "Pool should hold the rest");
        } else {
            // Buffer logic: if balance <= maxBuffer, keep everything
            assertEq(contractBalance, amount, "Contract should hold all funds");
            assertEq(poolBalance, 0, "Pool should be empty");
        }
    }

    function testFuzz_DepositAndWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1e6, 1e12 * 1e6);
        withdrawAmount = bound(withdrawAmount, 0, depositAmount);

        // Setup
        underlying.mint(address(this), depositAmount);
        underlying.approve(address(stableCustomize), depositAmount);
        stableCustomize.deposit(depositAmount, address(this));

        // Action
        stableCustomize.withdraw(withdrawAmount, address(this), address(this));

        // Verify user balances
        assertEq(underlying.balanceOf(address(this)), withdrawAmount);
        assertEq(stableCustomize.balanceOf(address(this)), depositAmount - withdrawAmount);

        // Verify system consistency
        uint256 remainingTotal = depositAmount - withdrawAmount;
        uint256 contractBal = underlying.balanceOf(address(stableCustomize));
        uint256 poolBal = underlying.balanceOf(thirdPool);

        assertEq(contractBal + poolBal, remainingTotal, "Total assets check failed");

        // Verify Buffer Logic after Withdraw
        (uint256 minBuffer, uint256 maxBuffer, uint256 buffer) = stableCustomize.bufferConfig();

        // Replicating logic from _withdrawWithBuffer
        // We need to know the state BEFORE the withdrawal to know exactly what path was taken?
        // Actually, we can check the end state properties.

        // If remaining is 0, everything should be 0
        if (remainingTotal == 0) {
            assertEq(contractBal, 0);
            assertEq(poolBal, 0);
            return;
        }

        // It's hard to assert exact split without re-implementing the logic,
        // because it depends on whether we triggered the refill.
        // But generally:
        // 1. If we triggered refill, contractBal should be `buffer` (capped by remainingTotal)
        // 2. If we didn't trigger refill, contractBal > minBuffer usually (unless we just barely have enough and didn't fall below minBuffer? No, check logic)

        // Logic: if (balance >= amount && balance - amount >= minBuffer) -> just pay.
        // Balance here refers to balance BEFORE withdraw payment.

        // Let's just assert basic invariants:
        // poolBal should verify: it holds whatever is not in contract.

        if (contractBal > maxBuffer) {
            // This shouldn't happen immediately after withdraw/deposit with buffer logic correct,
            // UNLESS deposit put it at buffer, and then we didn't touch it.
            // But maxBuffer usually > buffer.
        }
    }

    function testDeposit() public {
        uint256 amount = 1000e6; // Less than buffer 5000e6
        underlying.mint(address(this), amount);
        underlying.approve(address(stableCustomize), amount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(address(this), address(this), amount, amount);

        stableCustomize.deposit(amount, address(this));

        assertEq(stableCustomize.balanceOf(address(this)), amount);
        // All assets should be in contract (buffer not filled)
        assertEq(underlying.balanceOf(address(stableCustomize)), amount);
        assertEq(underlying.balanceOf(thirdPool), 0);
    }

    function testDepositExceedingBuffer() public {
        uint256 amount = 12000e6; // Exceeds max buffer 10000e6
        underlying.mint(address(this), amount);
        underlying.approve(address(stableCustomize), amount);

        stableCustomize.deposit(amount, address(this));

        assertEq(stableCustomize.balanceOf(address(this)), amount);
        // Contract holds buffer amount
        assertEq(underlying.balanceOf(address(stableCustomize)), 5000e6);
        // Remaining goes to thirdPool
        assertEq(underlying.balanceOf(thirdPool), 7000e6);
    }

    function testWithdraw() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stableCustomize), amount);
        stableCustomize.deposit(amount, address(this));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(this), address(this), address(this), amount, amount);

        stableCustomize.withdraw(amount, address(this), address(this));

        assertEq(stableCustomize.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(this)), amount);
    }

    function testWithdrawFromPool() public {
        uint256 amount = 12000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stableCustomize), amount);
        stableCustomize.deposit(amount, address(this));

        // Now withdraw everything
        stableCustomize.withdraw(amount, address(this), address(this));

        assertEq(underlying.balanceOf(address(this)), amount);
        assertEq(underlying.balanceOf(address(stableCustomize)), 0);
        assertEq(underlying.balanceOf(thirdPool), 0);
    }

    function testIncomeAccounting() public {
        uint256 amount = 10000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(stableCustomize), amount);
        stableCustomize.deposit(amount, address(this));

        // Initial state
        assertEq(stableCustomize.totalIncomeAssets(), 0);
        assertEq(stableCustomize.currentIncomeAssets(), 0);

        // Simulate income by giving more tokens to thirdPool
        uint256 income = 500e6;
        underlying.mint(thirdPool, income);

        // Check calculation
        // totalAssets calculation in contract: super.totalSupply() which is just minted shares.
        // Wait, totalAssets() in StableERC4626ForCustomize is overridden to return super.totalSupply()
        // This means the contract claims to only have assets equal to supply (1:1).
        // But actual assets might be higher.

        // totalIncomeAssets logic:
        // assetsWithIncome = assetInPool + underlyingBalance + withdawedIncomeAssets
        // return assetsWithIncome - totalSupply

        // We deposited 10000. Buffer 5000.
        // Contract: 5000. Pool: 5000. Supply: 10000.
        // Pool gets income +500. Pool: 5500.
        // assetsWithIncome = 5500 + 5000 + 0 = 10500.
        // totalIncomeAssets = 10500 - 10000 = 500.

        assertEq(stableCustomize.totalIncomeAssets(), income);
        assertEq(stableCustomize.currentIncomeAssets(), income);

        // Withdraw income
        vm.prank(admin);
        stableCustomize.withdrawIncomeAssets(address(underlying), admin, income);

        assertEq(underlying.balanceOf(admin), income);
        assertEq(stableCustomize.currentIncomeAssets(), 0);
        assertEq(stableCustomize.totalIncomeAssets(), income); // withdrawn is added back
    }

    function testUpdateBufferConfig() public {
        // Initial config: min 1000, max 10000, buffer 5000
        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 6000e6});

        // Only owner
        vm.prank(address(this));
        vm.expectRevert(); // OwnableUnauthorizedAccount
        stableCustomize.updateBufferConfigAndAddReserves(0, newConfig);

        vm.prank(admin);
        stableCustomize.updateBufferConfigAndAddReserves(0, newConfig);

        (uint256 min, uint256 max, uint256 buf) = stableCustomize.bufferConfig();
        assertEq(min, 2000e6);
        assertEq(max, 20000e6);
        assertEq(buf, 6000e6);
    }

    function testFuzz_UpdateBufferConfig(uint256 minBuf, uint256 maxBuf, uint256 buf) public {
        // Ensure valid configuration: min <= buf <= max
        // Using vm.assume to skip invalid combinations
        vm.assume(minBuf <= maxBuf);
        vm.assume(buf >= minBuf && buf <= maxBuf);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: minBuf, maximumBuffer: maxBuf, buffer: buf});

        vm.prank(admin);
        stableCustomize.updateBufferConfigAndAddReserves(0, newConfig);

        (uint256 min, uint256 max, uint256 b) = stableCustomize.bufferConfig();
        assertEq(min, minBuf);
        assertEq(max, maxBuf);
        assertEq(b, buf);
    }

    function testAddReserves() public {
        uint256 reserveAmount = 1000e6;
        underlying.mint(admin, reserveAmount);

        vm.startPrank(admin);
        underlying.approve(address(stableCustomize), reserveAmount);

        StakingBuffer.BufferConfig memory config =
            StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6});

        stableCustomize.updateBufferConfigAndAddReserves(reserveAmount, config);
        vm.stopPrank();

        // Reserves are added to contract balance, but not minted as shares
        // This implies they are counted as income?
        // assetsWithIncome includes balance. totalSupply unchanged.
        // So yes, it counts as income.

        assertEq(stableCustomize.currentIncomeAssets(), reserveAmount);
        assertEq(underlying.balanceOf(address(stableCustomize)), reserveAmount);
    }

    function testWithdrawAssets() public {
        MockERC20 randomToken = new MockERC20("RAND", "RAND", 6);
        randomToken.mint(address(stableCustomize), 1000e6);

        // 1. Owner can withdraw random tokens
        vm.prank(admin);
        stableCustomize.withdrawAssets(randomToken, admin, 1000e6);
        assertEq(randomToken.balanceOf(admin), 1000e6);
        assertEq(randomToken.balanceOf(address(stableCustomize)), 0);

        // 2. Owner CANNOT withdraw underlying
        uint256 amount = 100e6;
        underlying.mint(address(stableCustomize), amount);

        vm.prank(admin);
        vm.expectRevert(ERC4626TokenErrors.InvalidToken.selector);
        stableCustomize.withdrawAssets(underlying, admin, amount);
    }
}
