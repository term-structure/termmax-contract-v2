// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket, MarketEvents} from "contracts/v1/TermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {
    IGearingToken, AbstractGearingToken, GearingTokenConstants
} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/v1/oracle/OracleAggregator.sol";
import {
    TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit, RouterErrors
} from "contracts/v1/router/TermMaxRouter.sol";
import {UniswapV3AdapterV2, ERC20SwapAdapterV2} from "contracts/v1/router/specAdapters/UniswapV3AdapterV2.sol";
import {PendleSwapV3AdapterV2} from "contracts/v1/router/specAdapters/PendleSwapV3AdapterV2.sol";
import {OdosV2AdapterV2, IOdosRouterV2} from "contracts/v1/router/specAdapters/OdosV2AdapterV2.sol";
import {ERC4626VaultAdapterV2} from "contracts/v1/router/specAdapters/ERC4626VaultAdapterV2.sol";
import {TermMaxOrder, ITermMaxOrder} from "contracts/v1/TermMaxOrder.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {RouterEvents} from "contracts/v1/events/RouterEvents.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

abstract contract GtBaseTest is ForkBaseTest {
    enum TokenType {
        General,
        Pendle,
        Morpho
    }

    struct SwapData {
        uint128 debtAmt;
        uint128 swapAmtIn;
        TokenType tokenType;
        SwapUnit[] leverageUnits;
        SwapUnit[] flashRepayUnits;
    }

    struct SwapAdapters {
        address uniswapAdapter;
        address pendleAdapter;
        address odosAdapter;
        address vaultAdapter;
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
        SwapData swapData;
        SwapAdapters swapAdapters;
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
        res.oracle.submitPendingOracle(
            address(res.marketInitialParams.collateral),
            IOracle.Oracle(res.collateralPriceFeed, res.collateralPriceFeed, 365 days)
        );
        res.oracle.submitPendingOracle(
            address(res.marketInitialParams.debtToken), IOracle.Oracle(res.debtPriceFeed, res.debtPriceFeed, 365 days)
        );

        res.oracle.acceptPendingOracle(address(res.marketInitialParams.collateral));
        res.oracle.acceptPendingOracle(address(res.marketInitialParams.debtToken));

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

        res.swapAdapters.uniswapAdapter =
            address(new UniswapV3AdapterV2(vm.parseJsonAddress(jsonData, ".routers.uniswapRouter")));
        res.swapAdapters.pendleAdapter =
            address(new PendleSwapV3AdapterV2(vm.parseJsonAddress(jsonData, ".routers.pendleRouter")));
        res.swapAdapters.odosAdapter =
            address(new OdosV2AdapterV2(vm.parseJsonAddress(jsonData, ".routers.odosRouter")));
        res.swapAdapters.vaultAdapter = address(new ERC4626VaultAdapterV2());
        res.router = deployRouter(res.marketInitialParams.admin);
        vm.label(address(res.router), "TermMaxRouter");
        res.router.setAdapterWhitelist(res.swapAdapters.uniswapAdapter, true);
        res.router.setAdapterWhitelist(res.swapAdapters.pendleAdapter, true);
        res.router.setAdapterWhitelist(res.swapAdapters.odosAdapter, true);
        res.router.setAdapterWhitelist(res.swapAdapters.vaultAdapter, true);
        res.swapData = _readSwapData(key);

        res.orderInitialAmount = vm.parseJsonUint(jsonData, string.concat(key, ".orderInitialAmount"));
        deal(address(res.debtToken), res.marketInitialParams.admin, res.orderInitialAmount);

        res.debtToken.approve(address(res.market), res.orderInitialAmount);
        res.market.mint(address(res.order), res.orderInitialAmount);

        vm.stopPrank();

        return res;
    }

    function _readSwapData(string memory key) internal returns (SwapData memory data) {
        data.tokenType = TokenType(vm.parseJsonUint(jsonData, string.concat(key, ".swapData.tokenType")));
        data.debtAmt = uint128(vm.parseJsonUint(jsonData, string.concat(key, ".swapData.debtAmt")));
        data.swapAmtIn = uint128(vm.parseJsonUint(jsonData, string.concat(key, ".swapData.swapAmtIn")));

        uint256 length = vm.parseJsonUint(jsonData, string.concat(key, ".swapData.length"));
        data.leverageUnits = new SwapUnit[](length);
        data.flashRepayUnits = new SwapUnit[](length);
        for (uint256 i = 0; i < length; i++) {
            data.leverageUnits[i] = _readSwapUnit(string.concat(key, ".swapData.leverageUnits.", vm.toString(i)));
            data.flashRepayUnits[i] = _readSwapUnit(string.concat(key, ".swapData.flashRepayUnits.", vm.toString(i)));
        }
    }

    function _readSwapUnit(string memory key) internal view returns (SwapUnit memory data) {
        data.adapter = vm.parseJsonAddress(jsonData, string.concat(key, ".adapter"));
        data.tokenIn = vm.parseJsonAddress(jsonData, string.concat(key, ".tokenIn"));
        data.tokenOut = vm.parseJsonAddress(jsonData, string.concat(key, ".tokenOut"));
        data.swapData = vm.parseJsonBytes(jsonData, string.concat(key, ".swapData"));
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

        uint256 gtId = res.router.borrowTokenFromCollateral(
            taker, res.market, collInAmt, orders, tokenAmtsWantBuy, maxDebtAmt, block.timestamp + 1 hours
        );
        (address owner, uint128 debtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
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
        vm.startPrank(Ownable(address(res.router)).owner());
        for (uint256 i = 0; i < units.length; i++) {
            res.router.setAdapterWhitelist(units[i].adapter, true);
        }
        vm.stopPrank();

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
        vm.label(taker, "Taker");
        vm.startPrank(Ownable(address(res.router)).owner());
        for (uint256 i = 0; i < units.length; i++) {
            res.router.setAdapterWhitelist(units[i].adapter, true);
        }
        vm.stopPrank();

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
            taker,
            res.market,
            orders,
            amtsToBuyXt,
            minXTOut,
            tokenAmtIn,
            uint128(maxLtv),
            units,
            block.timestamp + 1 hours
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
        vm.startPrank(Ownable(address(res.router)).owner());
        for (uint256 i = 0; i < units.length; i++) {
            res.router.setAdapterWhitelist(units[i].adapter, true);
        }
        vm.stopPrank();

        deal(taker, 1e18);

        vm.startPrank(Ownable(address(res.router)).owner());
        for (uint256 i = 0; i < units.length; i++) {
            res.router.setAdapterWhitelist(units[i].adapter, true);
        }
        vm.stopPrank();

        vm.startPrank(taker);

        res.gt.approve(address(res.router), gtId);

        uint256 debtTokenBalanceBeforeRepay = res.debtToken.balanceOf(taker);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](0);
        uint128[] memory amtsToBuyFt = new uint128[](0);
        bool byDebtToken = true;

        uint256 netTokenOut = res.router.flashRepayFromColl(
            taker, res.market, gtId, orders, amtsToBuyFt, byDebtToken, units, block.timestamp + 1 hours
        );

        uint256 debtTokenBalanceAfterRepay = res.debtToken.balanceOf(taker);

        assertEq(debtTokenBalanceAfterRepay - debtTokenBalanceBeforeRepay, netTokenOut);

        vm.stopPrank();
    }

    function _testFlashRepayByFt(GtTestRes memory res, uint256 gtId, address taker, SwapUnit[] memory units) internal {
        vm.startPrank(Ownable(address(res.router)).owner());
        for (uint256 i = 0; i < units.length; i++) {
            res.router.setAdapterWhitelist(units[i].adapter, true);
        }
        vm.stopPrank();

        deal(taker, 1e18);

        vm.startPrank(taker);
        res.gt.approve(address(res.router), gtId);

        uint256 debtTokenBalanceBeforeRepay = res.debtToken.balanceOf(taker);
        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amtsToBuyFt = new uint128[](1);

        (, uint128 debtAmt,) = res.gt.loanInfo(gtId);
        amtsToBuyFt[0] = debtAmt;
        bool byDebtToken = false;

        uint256 netTokenOut = res.router.flashRepayFromColl(
            taker, res.market, gtId, orders, amtsToBuyFt, byDebtToken, units, block.timestamp + 1 hours
        );

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

        (, uint128 debtAmt,) = res.gt.loanInfo(gtId);

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
