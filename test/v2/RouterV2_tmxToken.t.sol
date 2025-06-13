// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {
    ITermMaxMarketV2, TermMaxMarketV2, Constants, MarketErrors, MarketEvents
} from "contracts/v2/TermMaxMarketV2.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";

import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {
    GearingTokenWithERC20V2,
    GearingTokenEvents,
    GearingTokenErrors,
    GearingTokenEventsV2,
    GtConfig
} from "contracts/v2/tokens/GearingTokenWithERC20V2.sol";
import {
    ITermMaxFactory,
    TermMaxFactoryV2,
    FactoryErrors,
    FactoryEvents,
    FactoryEventsV2
} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {IOracleV2, OracleAggregatorV2, AggregatorV3Interface} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {
    VaultInitialParams,
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCuts
} from "contracts/v1/storage/TermMaxStorage.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {MockFlashRepayerV2} from "contracts/v2/test/MockFlashRepayerV2.sol";
import {ISwapCallback} from "contracts/v1/ISwapCallback.sol";
import {
    TermMaxRouterV2,
    ITermMaxRouterV2,
    SwapUnit,
    RouterErrors,
    RouterEvents,
    SwapPath
} from "contracts/v2/router/TermMaxRouterV2.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {MockSwapAdapterV2} from "contracts/v2/test/MockSwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {TermMaxSwapData, TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {TermMaxTokenAdapter} from "contracts/v2/router/swapAdapters/TermMaxTokenAdapter.sol";

contract RouterTestV2_tmxToken is Test {
    using JSONLoader for *;
    using SafeCast for *;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address maker = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    address pool = vm.randomAddress();

    MockSwapAdapterV2 adapter;
    TermMaxSwapAdapter termMaxSwapAdapter;
    TermMaxTokenAdapter termMaxTokenAdapter;

    DeployUtils.Res res2;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployTermMaxTokenMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order =
            res.market.createOrder(maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint256 amount = 150e8;
        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.tmxToken), amount);
        res.tmxToken.mint(deployer, amount);
        res.tmxToken.approve(address(res.market), amount);
        res.market.mint(deployer, amount);
        res.ft.transfer(address(res.order), amount);
        res.xt.transfer(address(res.order), amount);

        res.router = DeployUtils.deployRouter(deployer);
        adapter = new MockSwapAdapterV2(pool);
        res.router.setAdapterWhitelist(address(adapter), true);

        termMaxSwapAdapter = new TermMaxSwapAdapter();
        res.router.setAdapterWhitelist(address(termMaxSwapAdapter), true);

        termMaxTokenAdapter = new TermMaxTokenAdapter();
        res.router.setAdapterWhitelist(address(termMaxTokenAdapter), true);

        vm.stopPrank();
    }

    function testSwapExactTokenToTokenWithWrap() public {
        vm.startPrank(sender);

        uint128 amountIn = 100e8;
        uint128[] memory tradingAmts = new uint128[](2);
        tradingAmts[0] = 50e8;
        tradingAmts[1] = 50e8;
        uint128 mintTokenOut = 80e8;

        address[] memory orders = new address[](2);
        orders[0] = address(res.order);
        orders[1] = address(res.order);

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: true,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: 80e8,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](2);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxTokenAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.tmxToken),
            swapData: abi.encode(true) // true indicates wrap operation
        });
        swapUnits[1] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.tmxToken),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: sender, inputAmount: amountIn, useBalanceOnchain: false});

        uint256[] memory netOutputs = res.router.swapTokens(swapPaths);

        assertEq(netOutputs[0], res.ft.balanceOf(sender));
        assertEq(res.debt.balanceOf(sender), 0);

        vm.stopPrank();
    }

    function testSwapExactTokenToTokenWithUnWrap() public {
        vm.startPrank(sender);

        uint128 amountIn = 100e8;
        uint128[] memory tradingAmts = new uint128[](2);
        tradingAmts[0] = 50e8;
        tradingAmts[1] = 50e8;
        uint128 mintTokenOut = 60e8;

        address[] memory orders = new address[](2);
        orders[0] = address(res.order);
        orders[1] = address(res.order);

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: true,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: 60e8,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        deal(address(res.ft), sender, amountIn); // mint FT tokens to sender
        res.ft.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](2);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.ft),
            tokenOut: address(res.tmxToken),
            swapData: abi.encode(swapData)
        });
        swapUnits[1] = SwapUnit({
            adapter: address(termMaxTokenAdapter),
            tokenIn: address(res.tmxToken),
            tokenOut: address(res.debt),
            swapData: abi.encode(false) // false indicates unwrap operation
        });

        uint256 ftBalanceBefore = res.ft.balanceOf(sender);
        uint256 debtBalanceBefore = res.debt.balanceOf(sender);

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: sender, inputAmount: amountIn, useBalanceOnchain: false});

        uint256[] memory netOutputs = res.router.swapTokens(swapPaths);

        assertEq(res.ft.balanceOf(sender), ftBalanceBefore - amountIn);
        assertEq(debtBalanceBefore + netOutputs[0], res.debt.balanceOf(sender));

        vm.stopPrank();
    }

    function testSwapTokenToExactTokenWithTmxToken() public {
        vm.startPrank(sender);
        // units 1: sender => usdc -> tmxToken -> ft => recipient
        // units 2: tmxToken -> usdc => recipient

        uint128 amountOut = 90e8;
        uint128[] memory tradingAmts = new uint128[](2);
        tradingAmts[0] = 45e8;
        tradingAmts[1] = 45e8;
        uint128 maxAmountIn = 100e8;

        address[] memory orders = new address[](2);
        orders[0] = address(res.order);
        orders[1] = address(res.order);

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: false,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: maxAmountIn,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, maxAmountIn);
        res.debt.approve(address(res.router), maxAmountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](2);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxTokenAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.tmxToken),
            swapData: abi.encode(true) // true indicates wrap operation
        });
        swapUnits[1] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.tmxToken),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });
        // directly send onchain balance to sender
        SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
        swapUnits2[0] = SwapUnit({
            adapter: address(termMaxTokenAdapter),
            tokenIn: address(res.tmxToken),
            tokenOut: address(res.debt),
            swapData: abi.encode(false)
        });

        SwapPath[] memory swapPaths = new SwapPath[](2);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: sender, inputAmount: maxAmountIn, useBalanceOnchain: false});
        // unwrap operation to get the debt token back
        swapPaths[1] = SwapPath({units: swapUnits2, recipient: sender, inputAmount: 0, useBalanceOnchain: true});

        uint256 balanceBefore = res.ft.balanceOf(sender);
        uint256[] memory netAmounts = res.router.swapTokens(swapPaths);
        uint256 amountIn = netAmounts[0];
        uint256 balanceAfter = res.ft.balanceOf(sender);

        assertEq(maxAmountIn - amountIn, res.debt.balanceOf(sender));
        assertEq(balanceAfter - balanceBefore, amountOut);

        vm.stopPrank();
    }
}
