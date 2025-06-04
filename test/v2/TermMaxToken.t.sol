// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxToken, StakingBuffer} from "contracts/v2/tokens/TermMaxToken.sol";
import {Test} from "forge-std/Test.sol";
import {MockAave} from "contracts/v2/test/MockAave.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract TermMaxTokenTest is Test {
    TermMaxToken public termMaxToken;
    MockAave public aavePool;
    MockERC20 public underlying;
    address public admin = vm.randomAddress();

    function setUp() public {
        underlying = new MockERC20("USDC", "USDC", 6);
        aavePool = new MockAave(address(underlying));

        vm.label(address(underlying), "USDC");
        vm.label(address(aavePool), "AavePool");
        vm.label(admin, "Admin");

        address implementation = address(new TermMaxToken(address(aavePool), 0));
        termMaxToken = TermMaxToken(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(
                        TermMaxToken.initialize.selector,
                        admin,
                        address(underlying),
                        StakingBuffer.BufferConfig({minimumBuffer: 1000e6, maximumBuffer: 10000e6, buffer: 5000e6})
                    )
                )
            )
        );

        vm.label(address(termMaxToken), "tmxUSDC");
    }

    function testMint() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);

        termMaxToken.mint(address(this), amount);

        assertEq(termMaxToken.balanceOf(address(this)), amount);
        assertEq(underlying.balanceOf(address(this)), 0);
        // Check that aTokens were minted to the TermMaxToken contract
        assertEq(aavePool.balanceOf(address(termMaxToken)), 0);
        assertEq(underlying.balanceOf(address(termMaxToken)), amount);
    }

    function testBurn() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        termMaxToken.burn(address(this), amount);

        assertEq(termMaxToken.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(this)), amount);
        assertEq(aavePool.balanceOf(address(termMaxToken)), 0);
    }

    function testBurnToAToken() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        vm.expectRevert();
        termMaxToken.burnToAToken(address(this), amount);

        underlying.mint(address(this), amount * 10);
        underlying.approve(address(termMaxToken), amount * 10);
        termMaxToken.mint(address(this), amount * 10);

        termMaxToken.burnToAToken(address(this), amount);

        assertEq(termMaxToken.balanceOf(address(this)), amount * 10);
        assertEq(aavePool.balanceOf(address(this)), amount);
    }

    function testWithdrawIncomeAssets() public {
        // Setup - mint some tokens
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Simulate yield by directly minting aTokens to the TermMaxToken contract
        uint256 yieldAmount = 100e6;
        aavePool.simulateInterestAccrual(address(termMaxToken), yieldAmount);

        // Withdraw income as the admin
        vm.startPrank(admin);
        termMaxToken.withdrawIncomeAssets(address(underlying), admin, yieldAmount);
        vm.stopPrank();

        // Assert balances are correct
        assertEq(underlying.balanceOf(admin), yieldAmount);
        assertEq(termMaxToken.totalIncomeAssets(), yieldAmount);
    }

    function testUpdateBufferConfigAndAddReserves() public {
        uint256 additionalReserves = 500e6;
        underlying.mint(admin, additionalReserves);

        vm.startPrank(admin);
        underlying.approve(address(termMaxToken), additionalReserves);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        termMaxToken.updateBufferConfigAndAddReserves(additionalReserves, newConfig);
        vm.stopPrank();

        // Get current buffer config
        (uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer) = termMaxToken.bufferConfig();

        // Assert the new config was set correctly
        assertEq(minimumBuffer, newConfig.minimumBuffer);
        assertEq(maximumBuffer, newConfig.maximumBuffer);
        assertEq(buffer, newConfig.buffer);

        // Assert the additional reserves were added
        assertEq(underlying.balanceOf(address(termMaxToken)), additionalReserves);
    }

    function testTotalIncomeAssets() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Simulate yield by directly minting aTokens to the TermMaxToken contract
        uint256 yieldAmount = 100e6;
        aavePool.simulateInterestAccrual(address(termMaxToken), yieldAmount);

        assertEq(termMaxToken.totalIncomeAssets(), yieldAmount);
    }

    function testMintZeroAmount() public {
        // The mint function doesn't explicitly check for zero amounts at the ERC20 level,
        // but it should revert due to transferFrom of zero amount or other validations
        underlying.mint(address(this), 0);
        underlying.approve(address(termMaxToken), 0);

        // This should succeed as minting 0 tokens is typically allowed
        termMaxToken.mint(address(this), 0);
        assertEq(termMaxToken.balanceOf(address(this)), 0);
    }

    function testBurnMoreThanBalance() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        vm.expectRevert();
        termMaxToken.burn(address(this), amount + 1);
    }

    function testWithdrawTooMuchIncome() public {
        // Setup - mint some tokens
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Simulate yield by directly minting aTokens to the TermMaxToken contract
        uint256 yieldAmount = 100e6;
        aavePool.simulateInterestAccrual(address(termMaxToken), yieldAmount);

        // Try to withdraw more than available income
        vm.startPrank(admin);
        vm.expectRevert();
        termMaxToken.withdrawIncomeAssets(address(underlying), admin, yieldAmount + 1);
        vm.stopPrank();
    }

    function testNonAdminCannotWithdrawIncome() public {
        // Setup - mint some tokens
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Simulate yield by directly minting aTokens to the TermMaxToken contract
        uint256 yieldAmount = 100e6;
        aavePool.simulateInterestAccrual(address(termMaxToken), yieldAmount);

        // Try to withdraw as non-admin
        vm.expectRevert();
        termMaxToken.withdrawIncomeAssets(address(underlying), address(this), yieldAmount);
    }

    function testNonAdminCannotUpdateBufferConfig() public {
        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        vm.expectRevert();
        termMaxToken.updateBufferConfigAndAddReserves(0, newConfig);
    }

    function testWithdrawIncomeAsAToken() public {
        // Setup - mint some tokens
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Simulate yield by directly minting aTokens to the TermMaxToken contract
        uint256 yieldAmount = 100e6;
        aavePool.simulateInterestAccrual(address(termMaxToken), yieldAmount);

        // Withdraw income as aToken
        vm.startPrank(admin);
        termMaxToken.withdrawIncomeAssets(address(aavePool), admin, yieldAmount);
        vm.stopPrank();

        // Assert balances are correct
        assertEq(aavePool.balanceOf(admin), yieldAmount);
    }

    function testWithdrawIncomeAsInvalidToken() public {
        // Setup
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18);

        // Attempt to withdraw income with invalid token
        vm.startPrank(admin);
        vm.expectRevert();
        termMaxToken.withdrawIncomeAssets(address(invalidToken), admin, 100e6);
        vm.stopPrank();
    }

    function testInvalidBufferConfiguration() public {
        vm.startPrank(admin);

        // Test minimum buffer greater than maximum buffer
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 10000e6, 5000e6, 7500e6));
        termMaxToken.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 10000e6, maximumBuffer: 5000e6, buffer: 7500e6})
        );

        // Test buffer outside min/max range (below minimum)
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 5000e6, 10000e6, 4000e6));
        termMaxToken.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 5000e6, maximumBuffer: 10000e6, buffer: 4000e6})
        );

        // Test buffer outside min/max range (above maximum)
        vm.expectRevert(abi.encodeWithSelector(StakingBuffer.InvalidBuffer.selector, 5000e6, 10000e6, 11000e6));
        termMaxToken.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 5000e6, maximumBuffer: 10000e6, buffer: 11000e6})
        );

        vm.stopPrank();
    }

    function testUnauthorizedAccess() public {
        address unauthorizedUser = vm.randomAddress();

        // Test unauthorized buffer config update
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        termMaxToken.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6})
        );
        vm.stopPrank();

        // Test unauthorized income withdrawal
        vm.startPrank(unauthorizedUser);
        vm.expectRevert();
        termMaxToken.withdrawIncomeAssets(address(termMaxToken), unauthorizedUser, 100e6);
        vm.stopPrank();
    }

    function testBurnToATokenInsufficientStaking() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Should revert when trying to burn to aToken without sufficient staking buffer
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(termMaxToken), 0, amount)
        );
        termMaxToken.burnToAToken(address(this), amount);
    }

    function testBurnToATokenExceedsBalance() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount * 20);
        underlying.approve(address(termMaxToken), amount * 20);
        termMaxToken.mint(address(this), amount * 20);

        // Should revert when trying to burn more than balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), amount * 20, amount * 21
            )
        );
        termMaxToken.burnToAToken(address(this), amount * 21);
    }

    function testMintWithInsufficientApproval() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount - 1); // Insufficient approval

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(termMaxToken), amount - 1, amount
            )
        );
        termMaxToken.mint(address(this), amount);
    }

    function testBurnWithInsufficientBalance() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        // Try to burn more than balance
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), amount, amount + 1)
        );
        termMaxToken.burn(address(this), amount + 1);
    }

    function testWithdrawIncomeToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);

        uint256 yieldAmount = 100e6;
        aavePool.simulateInterestAccrual(address(termMaxToken), yieldAmount);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        termMaxToken.withdrawIncomeAssets(address(underlying), address(0), yieldAmount);
        vm.stopPrank();
    }

    function testMintToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        termMaxToken.mint(address(0), amount);
    }

    function testBurnToZeroAddress() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);
        termMaxToken.mint(address(this), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        termMaxToken.burn(address(0), amount);
    }

    function testUpdateBufferWithInsufficientBalance() public {
        uint256 additionalReserves = 500e6;
        // Don't mint tokens to admin

        vm.startPrank(admin);
        underlying.approve(address(termMaxToken), additionalReserves);

        StakingBuffer.BufferConfig memory newConfig =
            StakingBuffer.BufferConfig({minimumBuffer: 2000e6, maximumBuffer: 20000e6, buffer: 10000e6});

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, admin, 0, additionalReserves)
        );
        termMaxToken.updateBufferConfigAndAddReserves(additionalReserves, newConfig);
        vm.stopPrank();
    }

    function testTermMaxTokenFuzzActions() public {
        vm.prank(admin);
        termMaxToken.updateBufferConfigAndAddReserves(
            0, StakingBuffer.BufferConfig({minimumBuffer: 500e6, maximumBuffer: 1000e6, buffer: 700e6})
        );

        address[] memory accounts = new address[](10);
        for (uint256 i = 0; i < accounts.length; i++) {
            accounts[i] = vm.addr(i + 1); // Create unique addresses for each account
        }
        uint256 totalInterest = 0;
        for (uint256 i = 0; i < 1000; i++) {
            uint256 amount = vm.randomUint(1e6, 1000000e6);
            address account = accounts[vm.randomUint(0, accounts.length - 1)];
            vm.startPrank(account);
            uint256 action = vm.randomUint(0, 2); // 0 for mint, 1 for burn

            uint256 underlyingBalanceBefore = underlying.balanceOf(account);
            uint256 tmxTokenBalanceBefore = termMaxToken.balanceOf(account);
            if (action == 0 || tmxTokenBalanceBefore < amount) {
                if (underlyingBalanceBefore < amount) {
                    underlying.mint(account, amount - underlyingBalanceBefore);
                }
                // Mint action
                underlying.mint(account, amount);
                underlying.approve(address(termMaxToken), amount);
                termMaxToken.mint(account, amount);
                assertEq(termMaxToken.balanceOf(account), amount + tmxTokenBalanceBefore);
            } else {
                // Burn action
                if (termMaxToken.balanceOf(account) >= amount) {
                    termMaxToken.burn(account, amount);
                    assertEq(termMaxToken.balanceOf(account), tmxTokenBalanceBefore - amount);
                    assertEq(underlying.balanceOf(account), underlyingBalanceBefore + amount);
                }
            }

            // Simulate interest accrual
            uint256 rate = vm.randomUint(0.01e8, 0.1e8);
            uint256 aTokenBalanceBefore = aavePool.balanceOf(address(termMaxToken));
            uint256 interest = (aTokenBalanceBefore * rate) / 1e8; // Interest accrued
            aavePool.simulateInterestAccrual(address(termMaxToken), interest);
            totalInterest += interest;
            vm.stopPrank();
        }

        assertEq(termMaxToken.totalIncomeAssets(), totalInterest);
        assertEq(
            underlying.balanceOf(address(termMaxToken)) + aavePool.balanceOf(address(termMaxToken)),
            totalInterest + termMaxToken.totalSupply()
        );
    }
}
