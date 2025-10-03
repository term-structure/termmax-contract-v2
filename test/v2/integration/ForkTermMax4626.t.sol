// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {
    IGearingToken,
    GearingTokenEvents,
    AbstractGearingToken,
    GtConfig
} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {
    ForkBaseTestV2,
    TermMaxFactoryV2,
    MarketConfig,
    IERC20,
    MarketInitialParams,
    IERC20Metadata
} from "test/v2/mainnet-fork/ForkBaseTestV2.sol";
import {console} from "forge-std/console.sol";
import {IAaveV3Pool} from "contracts/v2/extensions/aave/IAaveV3Pool.sol";
import {StableERC4626ForAave} from "contracts/v2/tokens/StableERC4626ForAave.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ForkTermMax4626 is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address aUSDC;
    IAaveV3Pool aave = IAaveV3Pool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    StableERC4626ForAave aave4626;
    StakingBuffer.BufferConfig stakingBuffer;
    address admin = vm.randomAddress();

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        stakingBuffer.minimumBuffer = 100e6;
        stakingBuffer.maximumBuffer = 1000e6;
        stakingBuffer.buffer = 500e6;
        address implementation = address(new StableERC4626ForAave(address(aave), 0));
        aave4626 = StableERC4626ForAave(
            address(
                new ERC1967Proxy(
                    implementation,
                    abi.encodeWithSelector(StableERC4626ForAave.initialize.selector, admin, usdc, stakingBuffer)
                )
            )
        );
        aUSDC = aave.getReserveData(usdc).aTokenAddress;

        vm.label(usdc, "USDC");
        vm.label(aUSDC, "aUSDC");
        vm.label(address(aave), "AavePool");
        vm.label(address(aave4626), "Aave4626");
        vm.label(admin, "Admin");
    }

    function test_withdraw(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount < 10_000_000e6);
        uint256 interest;
        uint256 withdrawAmount;
        uint256 withdrawInterest;
        bound(withdrawAmount, 1, depositAmount);
        bound(interest, 0, depositAmount / 10);
        bound(withdrawInterest, 0, interest);

        address user = vm.addr(1);
        vm.label(user, "User");
        vm.startPrank(user);
        deal(usdc, user, depositAmount);
        IERC20(usdc).approve(address(aave4626), type(uint256).max);
        aave4626.deposit(depositAmount, user);
        if (interest > 0) {
            deal(usdc, user, interest);
            IERC20(usdc).approve(address(aave), type(uint256).max);
            aave.supply(usdc, interest, address(aave4626), 0);
        }
        vm.stopPrank();

        if (withdrawInterest > aave4626.totalIncomeAssets()) {
            withdrawInterest = aave4626.totalIncomeAssets();
        }

        if (depositAmount % 2 != 0) {
            vm.prank(user);
            aave4626.redeem(withdrawAmount, user, user);
            if (withdrawInterest > 0) {
                vm.prank(admin);
                aave4626.withdrawIncomeAssets(usdc, admin, withdrawInterest);
            }
        } else {
            if (withdrawInterest > 0) {
                vm.prank(admin);
                aave4626.withdrawIncomeAssets(usdc, admin, withdrawInterest);
            }
            vm.prank(user);
            aave4626.redeem(withdrawAmount, user, user);
        }
        assertEq(IERC20(usdc).balanceOf(user), withdrawAmount, "user balance after withdraw");
        assertEq(IERC20(usdc).balanceOf(admin), withdrawInterest, "admin balance after withdraw income");
        uint256 totalAssets = IERC20(usdc).balanceOf(address(aave4626)) + IERC20(aUSDC).balanceOf(address(aave4626));
        uint256 totalRemaining = depositAmount - withdrawAmount + interest - withdrawInterest;
        assertApproxEqAbs(totalAssets, totalRemaining, 10, "total assets remaining in vault");
    }
}
