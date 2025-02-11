// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket, MarketEvents} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IGearingToken, AbstractGearingToken, GearingTokenConstants} from "contracts/tokens/AbstractGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit, RouterErrors} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {EnvConfig} from "test/mainnet-fork/EnvConfig.sol";
import {TermMaxOrder, ITermMaxOrder} from "contracts/TermMaxOrder.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {RouterEvents} from "contracts/events/RouterEvents.sol";
import {MockFlashLoanReceiver} from "contracts/test/MockFlashLoanReceiver.sol";
import "contracts/storage/TermMaxStorage.sol";

abstract contract GtBaseTest is ForkBaseTest {
    address maker = vm.randomAddress();
    MarketInitialParams marketInitialParams;
    uint256 maxXtReserve = type(uint128).max;

    TermMaxMarket market;
    IMintableERC20 ft;
    IMintableERC20 xt;
    IGearingToken gt;
    IERC20 collateral;
    IERC20 debtToken;
    IOracle oracle;
    MockPriceFeed collateralPriceFeed;
    MockPriceFeed debtPriceFeed;
    ITermMaxOrder order;
    ITermMaxRouter router;

    UniswapV3Adapter uniswapAdapter;
    PendleSwapV3Adapter pendleAdapter;
    OdosV2Adapter odosAdapter;

    function _initialize(bytes memory data) internal override {
        deal(maker, 1e18);
        CurveCuts memory curveCuts;
        (marketInitialParams, curveCuts) = abi.decode(data, (MarketInitialParams, CurveCuts));

        vm.startPrank(marketInitialParams.admin);

        oracle = deployOracleAggregator(marketInitialParams.admin);
        collateralPriceFeed = deployMockPriceFeed(marketInitialParams.admin);
        debtPriceFeed = deployMockPriceFeed(marketInitialParams.admin);
        oracle.setOracle(
            address(marketInitialParams.collateral), IOracle.Oracle(collateralPriceFeed, collateralPriceFeed, 365 days)
        );
        oracle.setOracle(address(marketInitialParams.debtToken), IOracle.Oracle(debtPriceFeed, debtPriceFeed, 365 days));

        marketInitialParams.marketConfig.maturity += uint64(block.timestamp);
        marketInitialParams.loanConfig.oracle = oracle;

        market = TermMaxMarket(
            deployFactory(marketInitialParams.admin).createMarket(
                keccak256("GearingTokenWithERC20"), marketInitialParams, 0
            )
        );

        (ft, xt, gt,,) = market.tokens();
        debtToken = marketInitialParams.debtToken;
        collateral = IERC20(marketInitialParams.collateral);

        order = market.createOrder(maker, maxXtReserve, ISwapCallback(address(0)), curveCuts);

        router = deployRouter(marketInitialParams.admin);

        router.setMarketWhitelist(address(market), true);

        vm.stopPrank();
    }

    function _testBorrow(uint256 collInAmt, uint128 borrowAmt, uint128 maxDebtAmt) internal {
        address taker = vm.randomAddress();

        vm.startPrank(taker);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory tokenAmtsWantBuy = new uint128[](1);
        tokenAmtsWantBuy[0] = borrowAmt;

        deal(address(collateral), taker, collInAmt);
        collateral.approve(address(router), collInAmt);

        uint256 gtId = router.borrowTokenFromCollateral(taker, market, collInAmt, orders, tokenAmtsWantBuy, maxDebtAmt);
        (address owner, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(gtId);
        assertEq(owner, taker);
        assertEq(collInAmt, abi.decode(collateralData, (uint256)));
        assertLe(debtAmt, maxDebtAmt);
        assertEq(debtToken.balanceOf(taker), borrowAmt);

        vm.stopPrank();
    }

    function _testLeverageFromXt(
        address taker,
        uint128 xtAmtIn,
        uint128 tokenAmtIn,
        SwapUnit[] memory units
    ) internal returns (uint256 gtId) {
        vm.startPrank(taker);
        deal(taker, 1e8);
        deal(address(debtToken), taker, xtAmtIn);
        debtToken.approve(address(market), xtAmtIn);
        market.mint(taker, xtAmtIn);

        uint256 maxLtv = marketInitialParams.loanConfig.maxLtv;

        deal(address(debtToken), taker, tokenAmtIn);
        debtToken.approve(address(router), tokenAmtIn);

        uint256 debtTokenBalanceBeforeSwap = debtToken.balanceOf(taker);
        uint256 xtAmtBeforeSwap = xt.balanceOf(taker);

        xt.approve(address(router), xtAmtIn);
        gtId = router.leverageFromXt(taker, market, xtAmtIn, tokenAmtIn, uint128(maxLtv), units);

        uint256 debtTokenBalanceAfterSwap = debtToken.balanceOf(taker);
        uint256 xtAmtAfterSwap = xt.balanceOf(taker);

        assertEq(debtTokenBalanceBeforeSwap - debtTokenBalanceAfterSwap, tokenAmtIn);
        assertEq(xtAmtBeforeSwap - xtAmtAfterSwap, xtAmtIn);

        assertEq(collateral.balanceOf(address(taker)), 0);

        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(xt.balanceOf(address(router)), 0);
        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(collateral.balanceOf(address(router)), 0);

        vm.stopPrank();
    }

    function _testLeverageFromToken(
        address taker,
        uint128 tokenAmtToBuyXt,
        uint128 tokenAmtIn,
        SwapUnit[] memory units
    ) internal returns (uint256 gtId) {
        vm.startPrank(taker);
        deal(taker, 1e8);

        uint256 maxLtv = marketInitialParams.loanConfig.maxLtv;
        uint128 minXTOut = 0e8;
        deal(address(debtToken), taker, tokenAmtToBuyXt + tokenAmtIn);
        debtToken.approve(address(router), tokenAmtToBuyXt + tokenAmtIn);

        uint256 debtTokenBalanceBeforeSwap = debtToken.balanceOf(taker);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory amtsToBuyXt = new uint128[](1);
        amtsToBuyXt[0] = tokenAmtToBuyXt;

        (gtId,) =
            router.leverageFromToken(taker, market, orders, amtsToBuyXt, minXTOut, tokenAmtIn, uint128(maxLtv), units);

        uint256 debtTokenBalanceAfterSwap = debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceBeforeSwap - debtTokenBalanceAfterSwap, tokenAmtToBuyXt + tokenAmtIn);

        assertEq(collateral.balanceOf(address(taker)), 0);

        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(xt.balanceOf(address(router)), 0);
        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(collateral.balanceOf(address(router)), 0);

        vm.stopPrank();
    }

    function _testFlashRepay(uint256 gtId, address taker, SwapUnit[] memory units) internal {
        deal(taker, 1e18);

        vm.startPrank(taker);

        gt.approve(address(router), gtId);

        uint256 debtTokenBalanceBeforeRepay = debtToken.balanceOf(taker);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](0);
        uint128[] memory amtsToBuyFt = new uint128[](0);
        bool byDebtToken = true;

        uint256 netTokenOut = router.flashRepayFromColl(taker, market, gtId, orders, amtsToBuyFt, byDebtToken, units);

        uint256 debtTokenBalanceAfterRepay = debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceAfterRepay - debtTokenBalanceBeforeRepay, netTokenOut);

        vm.stopPrank();
    }

    function _testFlashRepayByFt(uint256 gtId, uint128 debtAmt, address taker, SwapUnit[] memory units) internal {
        deal(taker, 1e18);

        vm.startPrank(taker);
        gt.approve(address(router), gtId);

        uint256 debtTokenBalanceBeforeRepay = debtToken.balanceOf(taker);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory amtsToBuyFt = new uint128[](1);
        amtsToBuyFt[0] = debtAmt;
        bool byDebtToken = false;

        uint256 netTokenOut = router.flashRepayFromColl(taker, market, gtId, orders, amtsToBuyFt, byDebtToken, units);

        uint256 debtTokenBalanceAfterRepay = debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceAfterRepay - debtTokenBalanceBeforeRepay, netTokenOut);

        vm.stopPrank();
    }

    function _testLiquidate(address liquidator, uint256 gtId) internal returns (uint256 collateralAmt) {
        deal(liquidator, 1e18);
        vm.startPrank(liquidator);

        (, uint128 debtAmt,,) = gt.loanInfo(gtId);

        deal(address(debtToken), liquidator, debtAmt);
        debtToken.approve(address(gt), debtAmt);

        collateralAmt = collateral.balanceOf(liquidator);

        bool byDebtToken = true;
        gt.liquidate(gtId, debtAmt, byDebtToken);

        collateralAmt = collateral.balanceOf(liquidator) - collateralAmt;

        vm.stopPrank();
    }

    function _fastLoan(address taker, uint256 debtAmt, uint256 collateralAmt) internal returns (uint256 gtId) {
        vm.startPrank(taker);
        deal(taker, 1e18);
        deal(address(collateral), taker, collateralAmt);
        collateral.approve(address(gt), collateralAmt);
        (gtId,) = market.issueFt(taker, uint128(debtAmt), abi.encode(collateralAmt));
        vm.stopPrank();
    }
}
