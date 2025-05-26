// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxToken, StakingBuffer} from "contracts/tokens/TermMaxToken.sol";
import {Test} from "forge-std/Test.sol";
import {MockAave} from "contracts/test/MockAave.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TermMaxTokenTest is Test {
    TermMaxToken public termMaxToken;
    MockAave public aavePool;
    MockERC20 public underlying;
    address public admin = vm.randomAddress();

    function setUp() public {
        underlying = new MockERC20("USDC", "USDC", 6);
        aavePool = new MockAave(address(underlying));

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
    }

    function testMint() public {
        uint256 amount = 1000e6;
        underlying.mint(address(this), amount);
        underlying.approve(address(termMaxToken), amount);

        termMaxToken.mint(address(this), amount);

        assertEq(termMaxToken.balanceOf(address(this)), amount);
        assertEq(underlying.balanceOf(address(this)), 0);
        // Check that aTokens were minted to the TermMaxToken contract
        assertEq(aavePool.balanceOf(address(termMaxToken)), amount);
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

        termMaxToken.burnToAToken(address(this), amount);

        assertEq(termMaxToken.balanceOf(address(this)), 0);
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
        assertEq(termMaxToken.totalIncomeAssets(), 0);
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
}
