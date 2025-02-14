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
import {TermMaxOrder, ITermMaxOrder} from "contracts/TermMaxOrder.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {RouterEvents} from "contracts/events/RouterEvents.sol";
import {MockFlashLoanReceiver} from "contracts/test/MockFlashLoanReceiver.sol";
import "contracts/storage/TermMaxStorage.sol";

abstract contract GtBaseTest is ForkBaseTest {
    struct LeverageAmountData {
        uint128 debtAmt;
        uint128 swapAmtIn;
    }

    struct UniswapData {
        address router;
        UniswapV3Adapter adapter;
        bool active;
        uint24 poolFee;
        LeverageAmountData leverageAmountData;
    }

    struct PendleSwapData {
        address router;
        PendleSwapV3Adapter adapter;
        bool active;
        address underlying;
        address pendleMarket;
    }

    struct OdosSwapData {
        address router;
        OdosV2Adapter adapter;
        bool active;
        address odosInputReceiver;
        uint256 outputQuote;
        uint256 outputMin;
        address odosExecutor;
        bytes odosPath;
        uint32 odosReferralCode;
        LeverageAmountData leverageAmountData;
    }

    struct GtTestRes {
        uint256 blockNumber;
        uint256 orderInitialAmount;
        MarketInitialParams marketInitialParams;
        OrderConfig orderConfig;
        TermMaxMarket market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IGearingToken gt;
        IERC20Metadata collateral;
        IERC20Metadata debtToken;
        IOracle oracle;
        MockPriceFeed collateralPriceFeed;
        MockPriceFeed debtPriceFeed;
        ITermMaxOrder order;
        ITermMaxRouter router;
        uint256 maxXtReserve;
        address maker;
        UniswapData uniswapData;
        PendleSwapData pendleData;
        OdosSwapData odosData;
    }

    function _initializeGtTestRes(string memory key) internal returns (GtTestRes memory) {
        GtTestRes memory res;
        res.blockNumber = _readBlockNumber(key);
        res.marketInitialParams = _readMarketInitialParams(key);
        res.orderConfig = _readOrderConfig(key);
        res.maker = vm.randomAddress();
        res.maxXtReserve = type(uint128).max;

        vm.rollFork(res.blockNumber);

        vm.startPrank(res.marketInitialParams.admin);

        res.oracle = deployOracleAggregator(res.marketInitialParams.admin);
        res.collateralPriceFeed = deployMockPriceFeed(res.marketInitialParams.admin);
        res.debtPriceFeed = deployMockPriceFeed(res.marketInitialParams.admin);
        res.oracle.setOracle(
            address(res.marketInitialParams.collateral),
            IOracle.Oracle(res.collateralPriceFeed, res.collateralPriceFeed, 365 days)
        );
        res.oracle.setOracle(
            address(res.marketInitialParams.debtToken), IOracle.Oracle(res.debtPriceFeed, res.debtPriceFeed, 365 days)
        );

        res.marketInitialParams.marketConfig.maturity += uint64(block.timestamp);
        res.marketInitialParams.loanConfig.oracle = res.oracle;

        res.market = TermMaxMarket(
            deployFactory(res.marketInitialParams.admin).createMarket(
                keccak256("GearingTokenWithERC20"), res.marketInitialParams, 0
            )
        );

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
        res.debtToken = res.marketInitialParams.debtToken;
        res.collateral = IERC20Metadata(res.marketInitialParams.collateral);

        // set all price as 1 USD = 1e8 tokens
        uint8 debtDecimals = res.debtToken.decimals();
        _setPriceFeedInTokenDecimal8(
            res.debtPriceFeed, debtDecimals, MockPriceFeed.RoundData(1, 1e8, block.timestamp, block.timestamp, 0)
        );
        uint8 collateralDecimals = res.collateral.decimals();
        _setPriceFeedInTokenDecimal8(
            res.collateralPriceFeed,
            collateralDecimals,
            MockPriceFeed.RoundData(1, 1e8, block.timestamp, block.timestamp, 0)
        );

        res.order =
            res.market.createOrder(res.maker, res.maxXtReserve, ISwapCallback(address(0)), res.orderConfig.curveCuts);

        res.router = deployRouter(res.marketInitialParams.admin);

        res.router.setMarketWhitelist(address(res.market), true);

        res.uniswapData = _readUniswapData(key);
        if (res.uniswapData.active) {
            res.router.setAdapterWhitelist(address(res.uniswapData.adapter), true);
        }
        res.pendleData = _readPendleSwapData(key);
        if (res.pendleData.active) {
            res.router.setAdapterWhitelist(address(res.pendleData.adapter), true);
        }
        res.odosData = _readOdosSwapData(key);
        if (res.odosData.active) {
            res.router.setAdapterWhitelist(address(res.odosData.adapter), true);
        }

        res.orderInitialAmount = vm.parseJsonUint(jsonData, string.concat(key, ".orderInitialAmount"));
        deal(address(res.debtToken), res.marketInitialParams.admin, res.orderInitialAmount);

        res.debtToken.approve(address(res.market), res.orderInitialAmount);
        res.market.mint(address(res.order), res.orderInitialAmount);

        vm.stopPrank();

        return res;
    }

    function _readUniswapData(string memory key) internal returns (UniswapData memory data) {
        data.active = vm.parseJsonBool(jsonData, string.concat(key, ".routers.uniswap.active"));
        if (data.active) {
            data.router = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.uniswap.address"));
            data.adapter = new UniswapV3Adapter(data.router);
            data.poolFee = uint24(vm.parseJsonUint(jsonData, string.concat(key, ".routers.uniswap.poolFee")));
            data.leverageAmountData.debtAmt =
                uint128(vm.parseJsonUint(jsonData, string.concat(key, ".routers.uniswap.leverage.debtAmt")));
            data.leverageAmountData.swapAmtIn =
                uint128(vm.parseJsonUint(jsonData, string.concat(key, ".routers.uniswap.leverage.swapAmtIn")));
        }
    }

    function _readPendleSwapData(string memory key) internal returns (PendleSwapData memory data) {
        data.active = vm.parseJsonBool(jsonData, string.concat(key, ".routers.pendle.active"));
        if (data.active) {
            data.router = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.pendle.address"));
            data.adapter = new PendleSwapV3Adapter(data.router);
            data.pendleMarket = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.pendle.market"));
            data.underlying = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.pendle.underlying"));
        }
    }

    function _readOdosSwapData(string memory key) internal returns (OdosSwapData memory data) {
        data.active = vm.parseJsonBool(jsonData, string.concat(key, ".routers.odos.active"));
        if (data.active) {
            data.router = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.odos.address"));
            data.adapter = new OdosV2Adapter(data.router);

            data.odosInputReceiver = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.odos.inputReceiver"));
            data.outputQuote = vm.parseJsonUint(jsonData, string.concat(key, ".routers.odos.outputQuote"));
            data.outputMin = vm.parseJsonUint(jsonData, string.concat(key, ".routers.odos.outputMin"));
            data.odosExecutor = vm.parseJsonAddress(jsonData, string.concat(key, ".routers.odos.executor"));
            data.odosPath = vm.parseJsonBytes(jsonData, string.concat(key, ".routers.odos.path"));
            data.odosReferralCode = uint32(vm.parseJsonUint(jsonData, string.concat(key, ".routers.odos.referralCode")));

            data.leverageAmountData.debtAmt =
                uint128(vm.parseJsonUint(jsonData, string.concat(key, ".routers.odos.leverage.debtAmt")));
            data.leverageAmountData.swapAmtIn =
                uint128(vm.parseJsonUint(jsonData, string.concat(key, ".routers.odos.leverage.swapAmtIn")));
        }
    }

    function _updateCollateralPrice(GtTestRes memory res, int256 price) internal {
        vm.startPrank(res.marketInitialParams.admin);
        // set all price as 1 USD = 1e8 tokens
        uint8 decimals = res.collateral.decimals();
        (uint80 roundId,,,,) = res.collateralPriceFeed.latestRoundData();
        roundId++;
        uint256 time = block.timestamp;
        _setPriceFeedInTokenDecimal8(
            res.collateralPriceFeed, decimals, MockPriceFeed.RoundData(roundId, price, time, time, 0)
        );
        vm.stopPrank();
    }

    function _testBorrow(GtTestRes memory res, uint256 collInAmt, uint128 borrowAmt, uint128 maxDebtAmt) internal {
        address taker = vm.randomAddress();

        vm.startPrank(taker);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory tokenAmtsWantBuy = new uint128[](1);
        tokenAmtsWantBuy[0] = borrowAmt;

        deal(address(res.collateral), taker, collInAmt);
        res.collateral.approve(address(res.router), collInAmt);

        uint256 gtId =
            res.router.borrowTokenFromCollateral(taker, res.market, collInAmt, orders, tokenAmtsWantBuy, maxDebtAmt);
        (address owner, uint128 debtAmt,, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, taker);
        assertEq(collInAmt, abi.decode(collateralData, (uint256)));
        assertLe(debtAmt, maxDebtAmt);
        assertEq(res.debtToken.balanceOf(taker), borrowAmt);

        vm.stopPrank();
    }

    function _testLeverageFromXt(
        GtTestRes memory res,
        address taker,
        uint128 xtAmtIn,
        uint128 tokenAmtIn,
        SwapUnit[] memory units
    ) internal returns (uint256 gtId) {
        vm.startPrank(taker);
        deal(taker, 1e8);
        deal(address(res.debtToken), taker, xtAmtIn);
        res.debtToken.approve(address(res.market), xtAmtIn);
        res.market.mint(taker, xtAmtIn);

        uint256 maxLtv = res.marketInitialParams.loanConfig.maxLtv;

        deal(address(res.debtToken), taker, tokenAmtIn);
        res.debtToken.approve(address(res.router), tokenAmtIn);

        uint256 debtTokenBalanceBeforeSwap = res.debtToken.balanceOf(taker);
        uint256 xtAmtBeforeSwap = res.xt.balanceOf(taker);

        res.xt.approve(address(res.router), xtAmtIn);
        gtId = res.router.leverageFromXt(taker, res.market, xtAmtIn, tokenAmtIn, uint128(maxLtv), units);

        uint256 debtTokenBalanceAfterSwap = res.debtToken.balanceOf(taker);
        uint256 xtAmtAfterSwap = res.xt.balanceOf(taker);

        assertEq(debtTokenBalanceBeforeSwap - debtTokenBalanceAfterSwap, tokenAmtIn);
        assertEq(xtAmtBeforeSwap - xtAmtAfterSwap, xtAmtIn);

        assertEq(res.collateral.balanceOf(taker), 0);

        assertEq(res.debtToken.balanceOf(address(res.router)), 0);
        assertEq(res.xt.balanceOf(address(res.router)), 0);
        assertEq(res.debtToken.balanceOf(address(res.router)), 0);
        assertEq(res.collateral.balanceOf(address(res.router)), 0);

        vm.stopPrank();
    }

    function _testLeverageFromToken(
        GtTestRes memory res,
        address taker,
        uint128 tokenAmtToBuyXt,
        uint128 tokenAmtIn,
        SwapUnit[] memory units
    ) internal returns (uint256 gtId) {
        vm.startPrank(taker);
        deal(taker, 1e8);

        uint256 maxLtv = res.marketInitialParams.loanConfig.maxLtv;
        uint128 minXTOut = 0e8;
        deal(address(res.debtToken), taker, tokenAmtToBuyXt + tokenAmtIn);
        res.debtToken.approve(address(res.router), tokenAmtToBuyXt + tokenAmtIn);

        uint256 debtTokenBalanceBeforeSwap = res.debtToken.balanceOf(taker);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amtsToBuyXt = new uint128[](1);
        amtsToBuyXt[0] = tokenAmtToBuyXt;

        (gtId,) = res.router.leverageFromToken(
            taker, res.market, orders, amtsToBuyXt, minXTOut, tokenAmtIn, uint128(maxLtv), units
        );

        uint256 debtTokenBalanceAfterSwap = res.debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceBeforeSwap - debtTokenBalanceAfterSwap, tokenAmtToBuyXt + tokenAmtIn);

        assertEq(res.collateral.balanceOf(taker), 0);

        assertEq(res.debtToken.balanceOf(address(res.router)), 0);
        assertEq(res.xt.balanceOf(address(res.router)), 0);
        assertEq(res.debtToken.balanceOf(address(res.router)), 0);
        assertEq(res.collateral.balanceOf(address(res.router)), 0);

        vm.stopPrank();
    }

    function _testFlashRepay(GtTestRes memory res, uint256 gtId, address taker, SwapUnit[] memory units) internal {
        deal(taker, 1e18);

        vm.startPrank(taker);

        res.gt.approve(address(res.router), gtId);

        uint256 debtTokenBalanceBeforeRepay = res.debtToken.balanceOf(taker);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](0);
        uint128[] memory amtsToBuyFt = new uint128[](0);
        bool byDebtToken = true;

        uint256 netTokenOut =
            res.router.flashRepayFromColl(taker, res.market, gtId, orders, amtsToBuyFt, byDebtToken, units);

        uint256 debtTokenBalanceAfterRepay = res.debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceAfterRepay - debtTokenBalanceBeforeRepay, netTokenOut);

        vm.stopPrank();
    }

    function _testFlashRepayByFt(
        GtTestRes memory res,
        uint256 gtId,
        uint128 debtAmt,
        address taker,
        SwapUnit[] memory units
    ) internal {
        deal(taker, 1e18);

        vm.startPrank(taker);
        res.gt.approve(address(res.router), gtId);

        uint256 debtTokenBalanceBeforeRepay = res.debtToken.balanceOf(taker);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amtsToBuyFt = new uint128[](1);
        amtsToBuyFt[0] = debtAmt;
        bool byDebtToken = false;

        uint256 netTokenOut =
            res.router.flashRepayFromColl(taker, res.market, gtId, orders, amtsToBuyFt, byDebtToken, units);

        uint256 debtTokenBalanceAfterRepay = res.debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceAfterRepay - debtTokenBalanceBeforeRepay, netTokenOut);

        vm.stopPrank();
    }

    function _testLiquidate(GtTestRes memory res, address liquidator, uint256 gtId)
        internal
        returns (uint256 collateralAmt)
    {
        deal(liquidator, 1e18);
        vm.startPrank(liquidator);

        (, uint128 debtAmt,,) = res.gt.loanInfo(gtId);

        deal(address(res.debtToken), liquidator, debtAmt);
        res.debtToken.approve(address(res.gt), debtAmt);

        collateralAmt = res.collateral.balanceOf(liquidator);

        bool byDebtToken = true;
        res.gt.liquidate(gtId, debtAmt, byDebtToken);

        collateralAmt = res.collateral.balanceOf(liquidator) - collateralAmt;

        vm.stopPrank();
    }

    function _fastLoan(GtTestRes memory res, address taker, uint256 debtAmt, uint256 collateralAmt)
        internal
        returns (uint256 gtId)
    {
        vm.startPrank(taker);
        deal(taker, 1e18);
        deal(address(res.collateral), taker, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        (gtId,) = res.market.issueFt(taker, uint128(debtAmt), abi.encode(collateralAmt));
        vm.stopPrank();
    }
}
