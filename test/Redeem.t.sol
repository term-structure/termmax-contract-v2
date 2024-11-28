// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, IERC20} from "../contracts/core/TermMaxMarket.sol";
import {MockFlashLoanReceiver} from "../contracts/test/MockFlashLoanReceiver.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {AbstractGearingToken} from "../contracts/core/tokens/AbstractGearingToken.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract RedeemTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;
    DeployUtils.Res res;

    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    uint32 redeemFeeRatio = 0.01e8;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        marketConfig = JSONLoader.getMarketConfigFromJson(
            treasurer,
            testdata,
            ".marketConfig"
        );
        marketConfig.redeemFeeRatio = redeemFeeRatio;
        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

        vm.warp(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.currentTime")
            )
        );

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_DAI_1.dai"
            )
        );

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(amount);

        vm.stopPrank();

        res.underlying.mint(sender, amount);

        vm.startPrank(sender);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(amount);
        vm.stopPrank();
    }

    function testRedeem() public {
        vm.startPrank(sender);
        // Add debt
        {
            uint128 debtAmt = 100e8;
            uint256 collateralAmt = 1e18;
            (uint256 gtId, ) = LoanUtils.fastMintGt(
                res,
                sender,
                debtAmt,
                collateralAmt
            );
            uint128 repayAmt = debtAmt / 10;
            res.ft.approve(address(res.gt), repayAmt);

            res.gt.repay(gtId, repayAmt, false);
        }
        // Do some swap
        {
            uint ftBalance = res.ft.balanceOf(sender);
            res.ft.approve(address(res.market), ftBalance);
            res.market.sellFt(uint128(ftBalance / 2), 0);

            uint lpXtBalance = res.lpXt.balanceOf(sender);
            res.lpXt.approve(address(res.market), lpXtBalance);

            res.market.withdrawLiquidity(0, uint128(lpXtBalance / 2));
        }

        assert(res.lpFt.balanceOf(address(res.market)) > 0);
        assert(res.lpXt.balanceOf(address(res.market)) > 0);
        assert(res.ft.balanceOf(address(res.gt)) > 0);

        vm.warp(marketConfig.maturity + Constants.LIQUIDATION_WINDOW);

        uint256[4] memory senderBalances = _getBalancesAndApproveAll(
            res,
            sender
        );
        (
            uint128 propotion,
            uint128 underlyingAmt,
            uint128 feeAmt,
            bytes memory deliveryData
        ) = StateChecker.getRedeemPoints(res, marketConfig, senderBalances);

        uint underlyingBefore = res.underlying.balanceOf(sender);
        uint collateralBefore = res.collateral.balanceOf(sender);
        vm.expectEmit();
        emit ITermMaxMarket.Redeem(
            sender,
            propotion,
            underlyingAmt,
            feeAmt,
            deliveryData
        );
        res.market.redeem(senderBalances);
        console.log("sender !");
        vm.stopPrank();
        uint underlyingAfter = res.underlying.balanceOf(sender);
        uint collateralAfter = res.collateral.balanceOf(sender);
        assertEq(underlyingBefore + underlyingAmt, underlyingAfter);
        assertEq(
            collateralBefore + abi.decode(deliveryData, (uint)),
            collateralAfter
        );

        vm.startPrank(deployer);
        uint[4] memory deployerBalances = _getBalancesAndApproveAll(
            res,
            deployer
        );
        (propotion, underlyingAmt, feeAmt, deliveryData) = StateChecker
            .getRedeemPoints(res, marketConfig, deployerBalances);
        vm.expectEmit();
        emit ITermMaxMarket.Redeem(
            deployer,
            propotion,
            underlyingAmt,
            feeAmt,
            deliveryData
        );
        res.market.redeem(deployerBalances);

        vm.startPrank(treasurer);

        uint[4] memory treasurerBalances = _getBalancesAndApproveAll(
            res,
            treasurer
        );
        (propotion, underlyingAmt, feeAmt, deliveryData) = StateChecker
            .getRedeemPoints(res, marketConfig, treasurerBalances);

        vm.expectEmit();
        emit ITermMaxMarket.Redeem(
            treasurer,
            propotion,
            underlyingAmt,
            feeAmt,
            deliveryData
        );
        res.market.redeem(treasurerBalances);
        vm.stopPrank();

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        assert(state.ftReserve == 0);
        assert(state.xtReserve == 0);
        assert(state.lpFtReserve == 0);
        assert(state.lpXtReserve == 0);
    }

    function testRevertByCanNotRedeemBeforeFinalLiquidationDeadline() public {
        vm.startPrank(sender);
        // Add debt
        {
            uint128 debtAmt = 100e8;
            uint256 collateralAmt = 1e18;
            (uint256 gtId, ) = LoanUtils.fastMintGt(
                res,
                sender,
                debtAmt,
                collateralAmt
            );
            uint128 repayAmt = debtAmt / 10;
            res.ft.approve(address(res.gt), repayAmt);

            res.gt.repay(gtId, repayAmt, false);
        }
        // Do some swap
        {
            uint ftBalance = res.ft.balanceOf(sender);
            res.ft.approve(address(res.market), ftBalance);
            res.market.sellFt(uint128(ftBalance / 2), 0);

            uint lpXtBalance = res.lpXt.balanceOf(sender);
            res.lpXt.approve(address(res.market), lpXtBalance);

            res.market.withdrawLiquidity(0, uint128(lpXtBalance / 2));
        }

        assert(res.lpFt.balanceOf(address(res.market)) > 0);
        assert(res.lpXt.balanceOf(address(res.market)) > 0);
        assert(res.ft.balanceOf(address(res.gt)) > 0);

        uint[4] memory balances = _getBalancesAndApproveAll(res, sender);

        vm.warp(marketConfig.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket
                    .CanNotRedeemBeforeFinalLiquidationDeadline
                    .selector,
                marketConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        res.market.redeem(balances);

        vm.warp(marketConfig.maturity - Constants.SECONDS_IN_DAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket
                    .CanNotRedeemBeforeFinalLiquidationDeadline
                    .selector,
                marketConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        res.market.redeem(balances);

        vm.stopPrank();
    }

    function _getBalancesAndApproveAll(
        DeployUtils.Res memory res_,
        address user
    ) internal returns (uint[4] memory balances) {
        uint256[6] memory balancesArray = StateChecker.getUserBalances(
            res_,
            user
        );
        balances = [
            balancesArray[0],
            balancesArray[1],
            balancesArray[2],
            balancesArray[3]
        ];
        res_.ft.approve(address(res_.market), balances[0]);
        res_.xt.approve(address(res_.market), balances[1]);
        res_.lpFt.approve(address(res_.market), balances[2]);
        res_.lpXt.approve(address(res_.market), balances[3]);
    }
}
