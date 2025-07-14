// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {VariableERC4626ForAave} from "contracts/v2/tokens/VariableERC4626ForAave.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {Test} from "forge-std/Test.sol";
import {MockAave} from "contracts/v2/test/MockAave.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract VariableERC4626ForAaveTest is Test {
    VariableERC4626ForAave public variableToken;
    MockAave public aavePool;
    MockERC20 public underlying;
    address public admin = vm.randomAddress();

    function setUp() public {
        underlying = new MockERC20("USDC", "USDC", 6);
        aavePool = new MockAave(address(underlying));

        vm.label(address(underlying), "USDC");
        vm.label(address(aavePool), "AavePool");
        vm.label(admin, "Admin");

        address implementation = address(new VariableERC4626ForAave(address(aavePool), 0));
        variableToken = VariableERC4626ForAave(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        VariableERC4626ForAave.initialize.selector,
                        admin,
                        address(underlying),
                        StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
                    )
                )
            )
        );

        vm.label(address(variableToken), "tmvaUSDC");
    }

    function testDeposit() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);

        uint256 shares = variableToken.deposit(amount, address(this));
        // Simulate interest accrual in Aave
        aavePool.simulateInterestAccrual(address(variableToken), amount / 10);

        assertEq(variableToken.balanceOf(address(this)), amount);
        assertEq(underlying.balanceOf(address(this)), 0);
        // The underlying should be deposited to Aave, not kept in the contract
        assertGt(variableToken.totalAssets(), amount); // Should include Aave deposits
        assertGt(variableToken.previewRedeem(shares), amount); // Should be able to redeem more than deposited due to interest accrual
    }

    function testRedeem() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);
        variableToken.deposit(amount, address(this));

        variableToken.redeem(amount, address(this), address(this));

        assertEq(variableToken.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(this)), amount);
    }

    function testUpdateBufferConfig() public {
        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        vm.startPrank(admin);
        variableToken.updateBufferConfig(newConfig);
        vm.stopPrank();

        // Get current buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = variableToken.bufferConfig();

        // Assert the new config was set correctly
        assertEq(minimumBuffer, newConfig.minimumBuffer);
        assertEq(maximumBuffer, newConfig.maximumBuffer);
        assertEq(buffer, newConfig.buffer);
    }

    function testDepositZeroAmount() public {
        underlying.mint(address(this), 0);
        underlying.approve(address(variableToken), 0);

        // This should succeed as depositing 0 tokens is typically allowed in ERC4626
        variableToken.deposit(0, address(this));
        assertEq(variableToken.balanceOf(address(this)), 0);
    }

    function testRedeemMoreThanBalance() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);
        variableToken.deposit(amount, address(this));

        vm.expectRevert();
        variableToken.redeem(amount + 1, address(this), address(this));
    }

    function testNonAdminCannotUpdateBufferConfig() public {
        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        vm.expectRevert();
        variableToken.updateBufferConfig(newConfig);
    }

    function testInvalidBufferConfiguration() public {
        vm.startPrank(admin);

        // Test minimum buffer greater than maximum buffer
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 10000e6, 5000e6, 7500e6));
        variableToken.updateBufferConfig(
            StakingBuffer.BufferConfig({minimumBuffer: 10000e6, maximumBuffer: 5000e6, buffer: 7500e6})
        );

        // Test buffer outside min/max range (below minimum)
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 5000e6, 10000e6, 4000e6));
        variableToken.updateBufferConfig(
            StakingBuffer.BufferConfig({minimumBuffer: 5000e6, maximumBuffer: 10000e6, buffer: 4000e6})
        );

        // Test buffer outside min/max range (above maximum)
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 5000e6, 10000e6, 11000e6));
        variableToken.updateBufferConfig(
            StakingBuffer.BufferConfig({minimumBuffer: 5000e6, maximumBuffer: 10000e6, buffer: 11000e6})
        );

        vm.stopPrank();
    }

    function testUnauthorizedAccess() public {
        address unauthorizedUser = vm.randomAddress();

        // Test unauthorized buffer config update
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        variableToken.updateBufferConfig(
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6})
        );
        vm.stopPrank();
    }

    function testDepositWithInsufficientApproval() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount - 1); // Insufficient approval

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(variableToken), amount - 1, amount
            )
        );
        variableToken.deposit(amount, address(this));
    }

    function testDepositToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        variableToken.deposit(amount, address(0));
    }

    function testRedeemToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);
        variableToken.deposit(amount, address(this));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        variableToken.redeem(amount, address(0), address(this));
    }

    function testTotalAssets() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);

        uint256 totalAssetsBefore = variableToken.totalAssets();

        variableToken.deposit(amount, address(this));

        uint256 totalAssetsAfter = variableToken.totalAssets();

        // Total assets should increase by the deposited amount
        assertEq(totalAssetsAfter - totalAssetsBefore, amount);
    }

    function testPreviewDeposit() public {
        uint256 amount = 1000e6;
        uint256 expectedShares = variableToken.previewDeposit(amount);

        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);

        variableToken.deposit(amount, address(this));

        assertEq(variableToken.balanceOf(address(this)), expectedShares);
    }

    function testPreviewRedeem() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(variableToken), amount);
        variableToken.deposit(amount, address(this));

        uint256 shares = variableToken.balanceOf(address(this));
        uint256 expectedAssets = variableToken.previewRedeem(shares);

        uint256 balanceBefore = underlying.balanceOf(address(this));
        variableToken.redeem(shares, address(this), address(this));
        uint256 balanceAfter = underlying.balanceOf(address(this));

        // Should be approximately equal (allowing for rounding)
        assertApproxEqAbs(balanceAfter - balanceBefore, expectedAssets, 1);
    }

    function testFuzzDepositRedeem() public {
        for (uint256 i = 0; i < 100; i++) {
            uint256 amount = vm.randomUint(1e6, 1000000e6);

            underlying.mint(address(this), amount);
            underlying.approve(address(variableToken), amount);

            uint256 shares = variableToken.deposit(amount, address(this));

            // Should be able to redeem what we deposited
            uint256 balanceBefore = underlying.balanceOf(address(this));
            variableToken.redeem(shares, address(this), address(this));
            uint256 balanceAfter = underlying.balanceOf(address(this));

            // Should get back approximately the same amount (allowing for rounding)
            assertApproxEqAbs(balanceAfter - balanceBefore, amount, shares / 1e6 + 1);
        }
    }
}
