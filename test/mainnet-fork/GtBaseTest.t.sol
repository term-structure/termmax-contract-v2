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
import {IGearingToken, AbstractGearingToken} from "contracts/tokens/AbstractGearingToken.sol";
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
        string memory testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));
        // update oracle
        collateralPriceFeed.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_PT_WEETH_1800.ptWeeth")
        );
        debtPriceFeed.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_PT_WEETH_1800.eth")
        );

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
        uint256 amount = 15000e8;
        deal(address(debtToken), maker, amount);

        debtToken.approve(address(market), amount);
        market.mint(address(order), amount);

        vm.stopPrank();
    }

    function _testLeverageFromXt(address taker, ISwapAdapter swapAdapter, SwapUnit[] memory units)
        internal
        returns (uint256 gtId)
    {
        vm.startPrank(taker);
        uint128 debtTokenAmtIn = 0.004e18;
        deal(address(debtToken), taker, debtTokenAmtIn);
        uint128 minTokenOut = 0e8;
        debtToken.approve(address(router), debtTokenAmtIn);

        uint256 debtTokenBalanceBeforeSwap = debtToken.balanceOf(taker);
        uint256 xtAmtBeforeSwap = xt.balanceOf(taker);
        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(xt.balanceOf(address(router)), 0);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 5e8;
        uint256 netXtOut = router.swapExactTokenToToken(debtToken, xt, taker, orders, amounts, uint128(minTokenOut));
        uint256 debtTokenBalanceAfterSwap = debtToken.balanceOf(taker);
        uint256 xtAmtAfterSwap = xt.balanceOf(taker);

        assertEq(debtTokenBalanceBeforeSwap - debtTokenBalanceAfterSwap, amounts[0]);
        assertEq(xtAmtAfterSwap - xtAmtBeforeSwap, netXtOut);
        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(xt.balanceOf(address(router)), 0);

        uint256 xtInAmt = netXtOut;

        uint256 tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;

        deal(address(debtToken), taker, tokenAmtIn);
        debtToken.approve(address(router), tokenAmtIn);

        debtTokenBalanceBeforeSwap = debtToken.balanceOf(taker);
        xtAmtBeforeSwap = xt.balanceOf(taker);

        assertEq(debtToken.balanceOf(address(taker)), 0);
        assertEq(collateral.balanceOf(address(taker)), 0);

        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(xt.balanceOf(address(router)), 0);
        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(collateral.balanceOf(address(router)), 0);

        xt.approve(address(router), xtInAmt);
        gtId = router.leverageFromXt(taker, market, uint128(xtInAmt), uint128(tokenAmtIn), uint128(maxLtv), units);

        debtTokenBalanceAfterSwap = debtToken.balanceOf(taker);
        xtAmtAfterSwap = xt.balanceOf(taker);

        assertEq(debtTokenBalanceBeforeSwap - debtTokenBalanceAfterSwap, tokenAmtIn);
        assertEq(xtAmtBeforeSwap - xtAmtAfterSwap, xtInAmt);

        assertEq(collateral.balanceOf(address(taker)), 0);

        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(xt.balanceOf(address(router)), 0);
        assertEq(debtToken.balanceOf(address(router)), 0);
        assertEq(collateral.balanceOf(address(router)), 0);

        vm.stopPrank();
    }

    function testLeverageFromToken(address taker) public {
        vm.startPrank(taker);
        uint128 underlyingAmtInForBuyXt = 5e8;
        uint256 tokenInAmt = 2e18;
        uint128 minXTOut = 0e8;
        uint256 maxLtv = 0.8e8;

        deal(address(debtToken), taker, underlyingAmtInForBuyXt + tokenInAmt);
        debtToken.approve(address(router), underlyingAmtInForBuyXt + tokenInAmt);
        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(abi.encodePacked(weth9Addr, poolFee, weethAddr), block.timestamp + 3600, 0)
        );
        units[1] = SwapUnit(address(pendleAdapter), weethAddr, ptWeethAddr, abi.encode(ptWeethMarketAddr, 0));

        uint256 underlyingAmtBeforeSwap = debtToken.balanceOf(taker);

        assert(res.collateral.balanceOf(address(taker)) == 0);
        assert(res.xt.balanceOf(address(taker)) == 0);
        assert(res.ft.balanceOf(address(taker)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(taker)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(taker)) == 0);

        assert(debtToken.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = res.order;
        uint128[] memory amtsToBuyXt = new uint128[](1);
        amtsToBuyXt[0] = underlyingAmtInForBuyXt;
        (gtId,) = router.leverageFromToken(
            receiver, res.market, orders, amtsToBuyXt, uint128(minXTOut), uint128(tokenInAmt), uint128(maxLtv), units
        );

        uint256 underlyingAmtAfterSwap = debtToken.balanceOf(taker);

        assert(underlyingAmtBeforeSwap - underlyingAmtAfterSwap == underlyingAmtInForBuyXt + tokenInAmt);

        assert(res.collateral.balanceOf(address(taker)) == 0);
        assert(res.xt.balanceOf(address(taker)) == 0);
        assert(res.ft.balanceOf(address(taker)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(taker)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(taker)) == 0);

        assert(debtToken.balanceOf(address(router)) == 0);
        assert(res.collateral.balanceOf(address(router)) == 0);
        assert(res.xt.balanceOf(address(router)) == 0);
        assert(res.ft.balanceOf(address(router)) == 0);
        assert(IERC20(weethAddr).balanceOf(address(router)) == 0);
        assert(IERC20(ptWeethAddr).balanceOf(address(router)) == 0);
        vm.stopPrank();
    }
}
