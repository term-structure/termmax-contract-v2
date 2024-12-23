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
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "../contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract RedeemTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;

    DeployUtils.Res res;

    TokenPairConfig tokenPairConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        tokenPairConfig = JSONLoader.getTokenPairConfigFromJson(treasurer, testdata, ".tokenPairConfig");
        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");

        tokenPairConfig.redeemFeeRatio = 0.01e8;

        res = DeployUtils.deployMarket(deployer, tokenPairConfig, marketConfig, maxLtv, liquidationLtv);
        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai")
        );

        uint amount = 150e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.tokenPair), amount);
        res.tokenPair.mintFtAndXt(deployer, deployer, amount);
        res.ft.transfer(address(res.market), amount);
        res.xt.transfer(address(res.market), amount);

        vm.stopPrank();
    }

    function testRedeem() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        (uint256 gtId, uint128 ftOutAmt) = res.tokenPair.issueFt(debtAmt, collateralData);
        uint128 repayAmt = debtAmt / 2;
        res.underlying.mint(sender, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);
        res.gt.repay(gtId, repayAmt, true);

        vm.warp(tokenPairConfig.maturity + Constants.LIQUIDATION_WINDOW);
        (IMintableERC20 ft, , , , IERC20 underlying) = res.tokenPair.tokens();
        uint propotion = (ftOutAmt * Constants.DECIMAL_BASE_SQ) / ft.totalSupply();
        uint underlyingAmt = (underlying.balanceOf(address(res.tokenPair)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint feeAmt = (underlyingAmt * tokenPairConfig.redeemFeeRatio) / Constants.DECIMAL_BASE;
        uint deliveryAmt = (res.collateral.balanceOf(address(res.gt)) * propotion) /
            Constants.DECIMAL_BASE_SQ;
        bytes memory deliveryData = abi.encode(deliveryAmt);
        res.ft.approve(address(res.tokenPair), ftOutAmt);

        StateChecker.TokenPairState memory state = StateChecker.getTokenPairState(res);
        vm.expectEmit();
        emit ITermMaxMarket.Redeem(
            address(sender),
            uint128(propotion),
            uint128(underlyingAmt - feeAmt),
            uint128(feeAmt),
            deliveryData
        );
        res.tokenPair.redeem(ftOutAmt);
        state.collateralReserve -= deliveryAmt;
        state.underlyingReserve -= underlyingAmt;
        StateChecker.checkTokenPairState(res, state);

        vm.stopPrank();
    }

    function testRevertByCanNotRedeemBeforeFinalLiquidationDeadline() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        (uint256 gtId, uint128 ftOutAmt) = res.tokenPair.issueFt(debtAmt, collateralData);
        uint128 repayAmt = debtAmt / 2;
        res.underlying.mint(sender, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);
        res.gt.repay(gtId, repayAmt, true);

        res.ft.approve(address(res.tokenPair), ftOutAmt);
        vm.warp(tokenPairConfig.maturity);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket
                    .CanNotRedeemBeforeFinalLiquidationDeadline
                    .selector,
                tokenPairConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        res.tokenPair.redeem(ftOutAmt);

        vm.warp(tokenPairConfig.maturity - Constants.SECONDS_IN_DAY);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket
                    .CanNotRedeemBeforeFinalLiquidationDeadline
                    .selector,
                tokenPairConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        res.tokenPair.redeem(ftOutAmt);

        vm.stopPrank();
    }

    // function _getBalancesAndApproveAll(
    //     DeployUtils.Res memory res_,
    //     address user
    // ) internal returns (uint[4] memory balances) {
    //     uint256[6] memory balancesArray = StateChecker.getUserBalances(res_, user);
    //     balances = [balancesArray[0], balancesArray[1], balancesArray[2], balancesArray[3]];
    //     res_.ft.approve(address(res_.market), balances[0]);
    //     res_.xt.approve(address(res_.market), balances[1]);
    //     res_.lpFt.approve(address(res_.market), balances[2]);
    //     res_.lpXt.approve(address(res_.market), balances[3]);
    // }
}
