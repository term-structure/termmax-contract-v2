// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
    FlashRepayOptions,
    SwapUnit,
    RouterErrors,
    RouterEvents,
    SwapPath,
    UUPSUpgradeable
} from "contracts/v2/router/TermMaxRouterV2.sol";
import {RouterEventsV2} from "contracts/v2/events/RouterEventsV2.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {MockSwapAdapterV2} from "contracts/v2/test/MockSwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {TermMaxSwapData, TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {TermMaxOrderV2, OrderInitialParams} from "contracts/v2/TermMaxOrderV2.sol";
import {DelegateAble} from "contracts/v2/lib/DelegateAble.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";

contract RouterTestV2 is Test {
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

    DeployUtils.Res res2;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order = TermMaxOrderV2(
            address(
                res.market.createOrder(
                    maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts
                )
            )
        );

        OrderInitialParams memory orderParams;
        orderParams.maker = maker;
        orderParams.orderConfig = orderConfig;
        uint256 amount = 150e8;
        orderParams.virtualXtReserve = amount;
        res.order = TermMaxOrderV2(address(res.market.createOrder(orderParams)));

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(deployer, amount);
        res.ft.transfer(address(res.order), amount);
        res.xt.transfer(address(res.order), amount);

        (res.router, res.whitelistManager) = DeployUtils.deployRouter(deployer);
        res.router.setWhitelistManager(address(res.whitelistManager));
        adapter = new MockSwapAdapterV2(pool);
        termMaxSwapAdapter = new TermMaxSwapAdapter(address(res.whitelistManager));

        address[] memory adapters = new address[](2);
        adapters[0] = address(adapter);
        adapters[1] = address(termMaxSwapAdapter);

        res.whitelistManager.batchSetWhitelist(adapters, IWhitelistManager.ContractModule.ADAPTER, true);

        vm.stopPrank();

        vm.prank(maker);
        res.order.updateOrder(orderConfig, 0, 0);
    }

    function testUpgradeRouterToV2() public {
        TermMaxRouterV2 impl = new TermMaxRouterV2();
        address admin = vm.randomAddress();
        bytes memory data = abi.encodeCall(TermMaxRouterV2.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        TermMaxRouterV2 router_tmp = TermMaxRouterV2(address(proxy));
        TermMaxRouterV2 impl2 = new TermMaxRouterV2();
        data = abi.encodeCall(TermMaxRouterV2.initializeV2, (vm.randomAddress()));

        vm.prank(admin);
        router_tmp.upgradeToAndCall(address(impl2), data);
    }

    function testSwapExactTokenToToken() public {
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
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: mintTokenOut,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
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

    function testSwapExactTokenToTokenWithWhitelistedCallbackAdnPool() public {
        {
            // deploy a mock callback and set it on the order as swapTrigger
            MockSwapCallback mockCallback = new MockSwapCallback();
            // deploy a mock pool and set it on the order
            MockERC4626 mockPool = new MockERC4626(res.debt);
            vm.startPrank(maker);
            res.order.setPool(IERC4626(address(mockPool)));
            res.order.setGeneralConfig(0, ISwapCallback(address(mockCallback)));
            vm.stopPrank();

            vm.startPrank(deployer);
            address[] memory callbacks = new address[](1);
            callbacks[0] = address(mockCallback);
            res.whitelistManager.batchSetWhitelist(callbacks, IWhitelistManager.ContractModule.ORDER_CALLBACK, true);
            address[] memory pools = new address[](1);
            pools[0] = address(mockPool);
            res.whitelistManager.batchSetWhitelist(pools, IWhitelistManager.ContractModule.POOL, true);
            vm.stopPrank();
        }

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
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: mintTokenOut,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
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
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: mintTokenOut,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
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

    function testSwapTokenToExactToken() public {
        vm.startPrank(sender);

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
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: maxAmountIn,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, maxAmountIn);
        res.debt.approve(address(res.router), maxAmountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });
        // directly send onchain balance to sender
        SwapUnit[] memory swapUnits2 = new SwapUnit[](1);
        swapUnits2[0] =
            SwapUnit({adapter: address(0), tokenIn: address(res.debt), tokenOut: address(0), swapData: bytes("")});

        SwapPath[] memory swapPaths = new SwapPath[](2);
        swapPaths[0] =
            SwapPath({units: swapUnits, recipient: sender, inputAmount: maxAmountIn, useBalanceOnchain: false});
        swapPaths[1] = SwapPath({units: swapUnits2, recipient: sender, inputAmount: 0, useBalanceOnchain: true});

        uint256 balanceBefore = res.ft.balanceOf(sender);
        uint256[] memory netAmounts = res.router.swapTokens(swapPaths);
        uint256 amountIn = netAmounts[0];
        uint256 balanceAfter = res.ft.balanceOf(sender);

        assertEq(maxAmountIn - amountIn, res.debt.balanceOf(sender));
        assertEq(balanceAfter - balanceBefore, amountOut);

        vm.stopPrank();
    }

    function testLeverageFromToken(bool isV1) public {
        vm.startPrank(sender);

        uint128 minXtOut = 0;
        uint128 tokenToSwap = 100e8;
        uint128 maxLtv = 0.8e8;
        uint256 minCollAmt = 1e18;
        res.debt.mint(sender, tokenToSwap + 2e8 * 2);

        address[] memory orders = new address[](2);
        orders[0] = address(res.order);
        orders[1] = address(res.order);

        uint128[] memory amtsToBuyXt = new uint128[](2);
        amtsToBuyXt[0] = 2e8;
        amtsToBuyXt[1] = 2e8;

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: true,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: amtsToBuyXt,
            netTokenAmt: minXtOut,
            deadline: block.timestamp + 1 hours
        });

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.xt),
            swapData: abi.encode(swapData)
        });

        SwapPath[] memory inputPaths = new SwapPath[](2);
        inputPaths[0] = SwapPath({
            units: swapUnits,
            recipient: address(res.router),
            inputAmount: amtsToBuyXt[0] + amtsToBuyXt[1],
            useBalanceOnchain: false
        });
        SwapUnit[] memory transferTokenUnits = new SwapUnit[](1);
        transferTokenUnits[0] = SwapUnit({
            adapter: address(0),
            tokenIn: address(res.debt),
            tokenOut: address(res.debt),
            swapData: bytes("")
        });
        inputPaths[1] = SwapPath({
            units: transferTokenUnits,
            recipient: address(res.router),
            inputAmount: tokenToSwap,
            useBalanceOnchain: false
        });

        SwapUnit[] memory swapCollateralUnits = new SwapUnit[](1);
        swapCollateralUnits[0] =
            SwapUnit(address(adapter), address(res.debt), address(res.collateral), abi.encode(minCollAmt));
        SwapPath memory collateralPath = SwapPath({
            units: swapCollateralUnits,
            recipient: address(res.router),
            inputAmount: 0,
            useBalanceOnchain: true
        });

        res.debt.approve(address(res.router), tokenToSwap + 2e8 * 2);

        // Check for IssueGt event
        // Only check indexed topics (market, gtId). Skip non-indexed data (caller, recipient, amounts, ltv, collData)
        vm.expectEmit(true, true, false, false);
        emit RouterEvents.IssueGt(res.market, 1, address(0), address(0), 0, 0, 0, "");

        (uint256 gtId, uint256 netXtOut) =
            res.router.leverage(sender, res.market, maxLtv, isV1, inputPaths, collateralPath);
        (address owner, uint128 debtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(minCollAmt, abi.decode(collateralData, (uint256)));
        assertEq(netXtOut * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio()), debtAmt);
        vm.stopPrank();
    }

    function testLeverageFromTokenAndXt(bool isV1) public {
        vm.startPrank(sender);

        uint128 xtAmt = 10e8;
        uint128 tokenToSwap = 100e8;
        uint128 maxLtv = 0.8e8;
        uint256 minCollAmt = 1e18;

        deal(address(res.xt), sender, xtAmt);
        res.xt.approve(address(res.router), xtAmt);
        res.debt.mint(sender, tokenToSwap);
        res.debt.approve(address(res.router), tokenToSwap);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(0), tokenIn: address(res.xt), tokenOut: address(res.xt), swapData: bytes("")});

        SwapPath[] memory inputPaths = new SwapPath[](2);
        inputPaths[0] =
            SwapPath({units: swapUnits, recipient: address(res.router), inputAmount: xtAmt, useBalanceOnchain: false});
        SwapUnit[] memory transferTokenUnits = new SwapUnit[](1);
        transferTokenUnits[0] = SwapUnit({
            adapter: address(0),
            tokenIn: address(res.debt),
            tokenOut: address(res.debt),
            swapData: bytes("")
        });
        inputPaths[1] = SwapPath({
            units: transferTokenUnits,
            recipient: address(res.router),
            inputAmount: tokenToSwap,
            useBalanceOnchain: false
        });

        SwapUnit[] memory swapCollateralUnits = new SwapUnit[](1);
        swapCollateralUnits[0] =
            SwapUnit(address(adapter), address(res.debt), address(res.collateral), abi.encode(minCollAmt));
        SwapPath memory collateralPath = SwapPath({
            units: swapCollateralUnits,
            recipient: address(res.router),
            inputAmount: 0,
            useBalanceOnchain: true
        });

        res.debt.approve(address(res.router), tokenToSwap + 2e8 * 2);
        (uint256 gtId, uint256 netXtOut) =
            res.router.leverage(sender, res.market, maxLtv, isV1, inputPaths, collateralPath);
        (address owner, uint128 debtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(minCollAmt, abi.decode(collateralData, (uint256)));
        assertEq(netXtOut * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio()), debtAmt);
        vm.stopPrank();
    }

    function testLeverageFromCollateralAndXt(bool isV1) public {
        vm.startPrank(sender);

        uint128 xtAmt = 10e8;
        uint128 collateralAmt = 0.5e18;
        uint128 maxLtv = 0.8e8;
        uint256 minCollAmt = 0.5e18;

        deal(address(res.xt), sender, xtAmt);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(0), tokenIn: address(res.xt), tokenOut: address(res.xt), swapData: bytes("")});

        SwapPath[] memory inputPaths = new SwapPath[](2);
        inputPaths[0] =
            SwapPath({units: swapUnits, recipient: address(res.router), inputAmount: xtAmt, useBalanceOnchain: false});
        SwapUnit[] memory transferTokenUnits = new SwapUnit[](1);
        transferTokenUnits[0] = SwapUnit({
            adapter: address(0),
            tokenIn: address(res.collateral),
            tokenOut: address(res.collateral),
            swapData: bytes("")
        });
        inputPaths[1] = SwapPath({
            units: transferTokenUnits,
            recipient: address(res.router),
            inputAmount: collateralAmt,
            useBalanceOnchain: false
        });

        SwapUnit[] memory swapCollateralUnits = new SwapUnit[](1);
        swapCollateralUnits[0] =
            SwapUnit(address(adapter), address(res.debt), address(res.collateral), abi.encode(minCollAmt));
        SwapPath memory collateralPath = SwapPath({
            units: swapCollateralUnits,
            recipient: address(res.router),
            inputAmount: 0,
            useBalanceOnchain: true
        });

        res.xt.approve(address(res.router), xtAmt);
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.router), collateralAmt);

        (uint256 gtId,) = res.router.leverage(sender, res.market, maxLtv, isV1, inputPaths, collateralPath);
        (address owner, uint128 debtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(minCollAmt + collateralAmt, abi.decode(collateralData, (uint256)));
        assertEq(
            uint128(xtAmt * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio())), debtAmt
        );
        vm.stopPrank();
    }

    function testLeverage_LtvTooBig(bool isV1) public {
        vm.startPrank(sender);

        uint128 xtAmt = 100e8;
        uint128 tokenToSwap = 100e8;
        uint128 maxLtv = 0.1e2;
        uint256 minCollAmt = 1e18;

        uint256 ltv = (xtAmt * Constants.DECIMAL_BASE / (Constants.DECIMAL_BASE - res.market.mintGtFeeRatio())) / 2000;

        deal(address(res.xt), sender, xtAmt);

        //paths to transfer xt and debt token
        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] =
            SwapUnit({adapter: address(0), tokenIn: address(res.xt), tokenOut: address(res.xt), swapData: bytes("")});

        SwapPath[] memory inputPaths = new SwapPath[](2);
        inputPaths[0] =
            SwapPath({units: swapUnits, recipient: address(res.router), inputAmount: xtAmt, useBalanceOnchain: false});
        SwapUnit[] memory transferTokenUnits = new SwapUnit[](1);
        transferTokenUnits[0] = SwapUnit({
            adapter: address(0),
            tokenIn: address(res.debt),
            tokenOut: address(res.debt),
            swapData: bytes("")
        });
        inputPaths[1] = SwapPath({
            units: transferTokenUnits,
            recipient: address(res.router),
            inputAmount: tokenToSwap,
            useBalanceOnchain: false
        });

        //path to swap collateral
        SwapUnit[] memory swapCollateralUnits = new SwapUnit[](1);
        swapCollateralUnits[0] =
            SwapUnit(address(adapter), address(res.debt), address(res.collateral), abi.encode(minCollAmt));
        SwapPath memory collateralPath = SwapPath({
            units: swapCollateralUnits,
            recipient: address(res.router),
            inputAmount: 0,
            useBalanceOnchain: true
        });

        res.xt.approve(address(res.router), xtAmt);
        res.debt.mint(sender, tokenToSwap);
        res.debt.approve(address(res.router), tokenToSwap);

        vm.expectRevert(
            abi.encodeWithSelector(RouterErrors.LtvBiggerThanExpected.selector, uint128(maxLtv), uint128(ltv))
        );
        res.router.leverage(sender, res.market, maxLtv, isV1, inputPaths, collateralPath);

        vm.stopPrank();
    }

    function testBorrowTokenFromCollateral() public {
        vm.startPrank(sender);

        uint256 collInAmt = 1e18;
        uint128 borrowAmt = 80e8;
        uint128 maxDebtAmt = 100e8;

        address[] memory orders = new address[](1);
        orders[0] = address(res.order);
        uint128[] memory tokenAmtsWantBuy = new uint128[](1);
        tokenAmtsWantBuy[0] = borrowAmt;

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: false,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tokenAmtsWantBuy,
            netTokenAmt: maxDebtAmt,
            deadline: block.timestamp + 1 hours
        });

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.ft),
            tokenOut: address(res.debt),
            swapData: abi.encode(swapData)
        });

        SwapPath memory ftPath =
            SwapPath({units: swapUnits, recipient: sender, inputAmount: 0, useBalanceOnchain: true});

        res.collateral.mint(sender, collInAmt);
        res.collateral.approve(address(res.router), collInAmt);

        uint256 gtId = res.router.borrowTokenFromCollateral(sender, res.market, collInAmt, maxDebtAmt, ftPath);

        (address owner, uint128 debtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(collInAmt, abi.decode(collateralData, (uint256)));
        assert(debtAmt <= maxDebtAmt);
        assertEq(res.debt.balanceOf(sender), borrowAmt);
        vm.stopPrank();
    }

    function testBorrowTokenFromCollateralAndXt(bool isV1) public {
        vm.startPrank(sender);

        uint256 collInAmt = 1e18;
        uint128 borrowAmt = 80e8;

        res.collateral.mint(sender, collInAmt);
        res.collateral.approve(address(res.router), collInAmt);

        res.debt.mint(sender, borrowAmt);
        res.debt.approve(address(res.market), borrowAmt);
        res.market.mint(sender, borrowAmt);

        res.xt.approve(address(res.router), borrowAmt);

        uint256 mintGtFeeRatio = res.market.mintGtFeeRatio();
        uint128 previewDebtAmt =
            ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        vm.expectEmit();
        emit RouterEvents.Borrow(res.market, 1, sender, sender, collInAmt, previewDebtAmt, borrowAmt);

        uint256 gtId = res.router.borrowTokenFromCollateralAndXt(sender, res.market, collInAmt, borrowAmt, isV1);
        (address owner, uint128 debtAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(collInAmt, abi.decode(collateralData, (uint256)));
        assert(previewDebtAmt == debtAmt);
        assertEq(res.debt.balanceOf(sender), borrowAmt);

        vm.stopPrank();
    }

    function testFlashRepayFromCollateral(bool isV1) public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, 1e18);
        (,, bytes memory collateralData) = res.gt.loanInfo(gtId);
        bool byDebtToken = true;
        uint256 collateralAmt = abi.decode(collateralData, (uint256));

        uint256 mintTokenOut = 2000e8;
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(address(adapter), address(res.collateral), address(res.debt), abi.encode(mintTokenOut));

        SwapPath memory swapPaths = SwapPath({
            units: units,
            recipient: address(res.router),
            inputAmount: collateralAmt,
            useBalanceOnchain: false
        });
        bytes memory callbackData = abi.encode(FlashRepayOptions.REPAY, abi.encode(swapPaths));
        res.gt.approve(address(res.router), gtId);

        // Check for FlashRepay event
        vm.expectEmit(true, true, true, true);
        emit RouterEventsV2.FlashRepay(address(res.gt), gtId, mintTokenOut - debtAmt);

        if (isV1) {
            res.router.flashRepayFromCollForV1(sender, res.market, gtId, byDebtToken, 0, callbackData);
        } else {
            res.router.flashRepayFromCollForV2(
                sender, res.market, gtId, debtAmt, byDebtToken, 0, collateralAmt, callbackData
            );
        }

        assertEq(res.collateral.balanceOf(sender), 0);
        assertEq(res.debt.balanceOf(sender), mintTokenOut - debtAmt);

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testFlashRepayFromCollateral_ByFt(bool isV1) public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, 1e18);
        (,, bytes memory collateralData) = res.gt.loanInfo(gtId);
        address[] memory orders = new address[](1);
        orders[0] = address(res.order);
        uint128[] memory amtsToBuyFt = new uint128[](1);
        amtsToBuyFt[0] = debtAmt;

        bool byDebtToken = false;
        uint256 collateralAmt = abi.decode(collateralData, (uint256));

        uint256 mintTokenOut = 2000e8;
        SwapUnit[] memory units = new SwapUnit[](2);
        units[0] = SwapUnit(address(adapter), address(res.collateral), address(res.debt), abi.encode(mintTokenOut));

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: false,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: amtsToBuyFt,
            netTokenAmt: mintTokenOut.toUint128(),
            deadline: block.timestamp + 1 hours
        });
        units[1] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });

        SwapPath memory swapPath = SwapPath({
            units: units,
            recipient: address(res.router),
            inputAmount: collateralAmt,
            useBalanceOnchain: false
        });
        bytes memory callbackData = abi.encode(FlashRepayOptions.REPAY, abi.encode(swapPath));

        res.gt.approve(address(res.router), gtId);
        if (isV1) {
            res.router.flashRepayFromCollForV1(sender, res.market, gtId, byDebtToken, 0, callbackData);
        } else {
            // DelegateAble(address(res.gt)).setDelegate(address(res.router), true);
            res.router.flashRepayFromCollForV2(
                sender, res.market, gtId, debtAmt, byDebtToken, 0, collateralAmt, callbackData
            );
        }

        assertEq(res.collateral.balanceOf(sender), 0);
        assert(res.debt.balanceOf(sender) > mintTokenOut - debtAmt);

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testFlashRepayFromCollateralPatrially() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt / 2);
        bool byDebtToken = true;

        uint256 mintTokenOut = debtAmt / 2;
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(address(adapter), address(res.collateral), address(res.debt), abi.encode(mintTokenOut));

        SwapPath memory swapPath = SwapPath({
            units: units,
            recipient: address(res.router),
            inputAmount: collateralAmt / 2,
            useBalanceOnchain: true
        });
        bytes memory callbackData = abi.encode(FlashRepayOptions.REPAY, abi.encode(swapPath));

        res.gt.approve(address(res.router), gtId);
        res.router.flashRepayFromCollForV2(
            sender, res.market, gtId, debtAmt / 2, byDebtToken, 0, abi.decode(collateralData, (uint256)), callbackData
        );

        assertEq(res.collateral.balanceOf(sender), 0);
        assertEq(res.debt.balanceOf(sender), 0);
        (address owner, uint128 remainingDebtAmt, bytes memory remainingCollateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(remainingDebtAmt, debtAmt - debtAmt / 2);
        assertEq(abi.decode(remainingCollateralData, (uint256)), collateralAmt - collateralAmt / 2);

        vm.stopPrank();
    }

    function testRepayByTokenThroughFt() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        address[] memory orders = new address[](1);
        orders[0] = address(res.order);
        uint128[] memory amtsToBuyFt = new uint128[](1);
        amtsToBuyFt[0] = debtAmt;
        uint128 maxTokenIn = debtAmt;

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: false,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: amtsToBuyFt,
            netTokenAmt: maxTokenIn,
            deadline: block.timestamp + 1 hours
        });

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });

        SwapPath[] memory inputPaths = new SwapPath[](2);
        inputPaths[0] =
            SwapPath({units: swapUnits, recipient: address(res.router), inputAmount: debtAmt, useBalanceOnchain: false});

        SwapUnit[] memory transferTokenUnits = new SwapUnit[](1);
        transferTokenUnits[0] =
            SwapUnit({adapter: address(0), tokenIn: address(res.debt), tokenOut: address(0), swapData: bytes("")});
        inputPaths[1] =
            SwapPath({units: transferTokenUnits, recipient: sender, inputAmount: 0, useBalanceOnchain: true});

        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.router), maxTokenIn);

        // Check for SwapAndRepay event
        vm.expectEmit(true, true, true, true);
        emit RouterEventsV2.SwapAndRepay(address(res.gt), gtId, debtAmt, 0);

        uint256 netCost = res.router.swapAndRepay(res.gt, gtId, debtAmt, false, inputPaths)[0];
        assertEq(res.debt.balanceOf(sender), maxTokenIn - netCost);
        assertEq(res.collateral.balanceOf(sender), collateralAmt);

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testPartialRepayByTokenThroughFt() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        (uint256 gtId,) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        address[] memory orders = new address[](1);
        orders[0] = address(res.order);
        uint128[] memory amtsToBuyFt = new uint128[](1);
        amtsToBuyFt[0] = debtAmt / 2;
        uint128 maxTokenIn = debtAmt;

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: false,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: amtsToBuyFt,
            netTokenAmt: maxTokenIn,
            deadline: block.timestamp + 1 hours
        });

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });

        SwapPath[] memory inputPaths = new SwapPath[](2);
        inputPaths[0] =
            SwapPath({units: swapUnits, recipient: address(res.router), inputAmount: debtAmt, useBalanceOnchain: false});

        SwapUnit[] memory transferTokenUnits = new SwapUnit[](1);
        transferTokenUnits[0] =
            SwapUnit({adapter: address(0), tokenIn: address(res.debt), tokenOut: address(0), swapData: bytes("")});
        inputPaths[1] =
            SwapPath({units: transferTokenUnits, recipient: sender, inputAmount: 0, useBalanceOnchain: true});

        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.router), maxTokenIn);

        uint256 netCost = res.router.swapAndRepay(res.gt, gtId, debtAmt / 2, false, inputPaths)[0];
        assertEq(res.debt.balanceOf(sender), maxTokenIn - netCost);
        assertEq(res.collateral.balanceOf(sender), 0);

        (address owner, uint128 dAmt, bytes memory collateralData) = res.gt.loanInfo(gtId);
        assertEq(owner, sender);
        assertEq(collateralAmt, abi.decode(collateralData, (uint256)));
        assertEq(dAmt, debtAmt / 2);

        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(deployer);

        res.router.pause();
        assertTrue(res.router.paused());

        res.router.unpause();
        assertFalse(res.router.paused());

        vm.stopPrank();
    }

    function testPauseUnauthorized() public {
        vm.startPrank(sender);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(sender)));
        res.router.pause();

        vm.stopPrank();
    }

    function testSwap_RevertWhenCallbackNotWhitelisted() public {
        // deploy a mock callback and set it on the order as swapTrigger
        MockSwapCallback mockCallback = new MockSwapCallback();
        vm.startPrank(maker);
        res.order.setGeneralConfig(0, ISwapCallback(address(mockCallback)));
        vm.stopPrank();

        vm.startPrank(sender);

        uint128 amountIn = 10e8;
        uint128[] memory tradingAmts = new uint128[](1);
        tradingAmts[0] = 10e8;

        address[] memory orders = new address[](1);
        orders[0] = address(res.order);

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: true,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: 1e8,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: sender, inputAmount: amountIn, useBalanceOnchain: false});
        bytes memory errorData =
            abi.encodeWithSelector(bytes4(keccak256("UnauthorizedCallback(address)")), address(mockCallback));

        vm.expectRevert(abi.encodeWithSelector(RouterErrors.SwapFailed.selector, termMaxSwapAdapter, errorData));
        res.router.swapTokens(swapPaths);

        vm.stopPrank();
    }

    function testSwap_RevertWhenPoolNotWhitelisted() public {
        // deploy a mock pool and set it on the order
        MockERC4626 mockPool = new MockERC4626(res.debt);
        vm.startPrank(maker);
        res.order.setPool(IERC4626(address(mockPool)));
        vm.stopPrank();

        vm.startPrank(sender);

        uint128 amountIn = 10e8;
        uint128[] memory tradingAmts = new uint128[](1);
        tradingAmts[0] = 10e8;

        address[] memory orders = new address[](1);
        orders[0] = address(res.order);

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: true,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: 1e8,
            deadline: block.timestamp + 1 hours
        });

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(res.debt),
            tokenOut: address(res.ft),
            swapData: abi.encode(swapData)
        });

        SwapPath[] memory swapPaths = new SwapPath[](1);
        swapPaths[0] = SwapPath({units: swapUnits, recipient: sender, inputAmount: amountIn, useBalanceOnchain: false});
        bytes memory errorData =
            abi.encodeWithSelector(bytes4(keccak256("UnauthorizedPool(address)")), address(mockPool));
        vm.expectRevert(abi.encodeWithSelector(RouterErrors.SwapFailed.selector, termMaxSwapAdapter, errorData));
        res.router.swapTokens(swapPaths);

        vm.stopPrank();
    }
}

// Minimal mock swap callback used by some tests in this file
contract MockSwapCallback is ISwapCallback {
    int256 public deltaFt;
    int256 public deltaXt;

    function afterSwap(uint256, uint256, int256 deltaFt_, int256 deltaXt_) external override {
        deltaFt = deltaFt_;
        deltaXt = deltaXt_;
    }
}
