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

contract RouterTestV2_1 is Test {
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

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order =
            res.market.createOrder(maker, orderConfig.maxXtReserve, ISwapCallback(address(0)), orderConfig.curveCuts);

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint256 amount = 150e8;
        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.market), amount);
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

    function testSellXtAndFt(bool isV1, uint128 ftAmount, uint128 xtAmount) public {
        vm.assume(ftAmount <= 150e8 && xtAmount <= 150e8);
        vm.startPrank(sender);
        deal(address(res.ft), sender, ftAmount);
        deal(address(res.xt), sender, xtAmount);

        address[] memory orders = new address[](2);
        orders[0] = address(res.order);
        orders[1] = address(res.order);

        (uint128 maxBurn, uint128 sellAmt) =
            ftAmount > xtAmount ? (xtAmount, ftAmount - xtAmount) : (ftAmount, xtAmount - ftAmount);
        IERC20 tokenToSell = ftAmount > xtAmount ? res.ft : res.xt;
        uint128[] memory tradingAmts = new uint128[](2);
        tradingAmts[0] = sellAmt / 2;
        tradingAmts[1] = sellAmt / 2;
        uint128 mintTokenOut = 0;

        res.ft.approve(address(res.router), ftAmount);
        res.xt.approve(address(res.router), xtAmount);

        TermMaxSwapData memory swapData = TermMaxSwapData({
            swapExactTokenForToken: true,
            scalingFactor: 0,
            orders: orders,
            tradingAmts: tradingAmts,
            netTokenAmt: mintTokenOut,
            deadline: block.timestamp + 1 hours
        });

        SwapUnit[] memory swapUnits = new SwapUnit[](1);
        swapUnits[0] = SwapUnit({
            adapter: address(termMaxSwapAdapter),
            tokenIn: address(tokenToSell),
            tokenOut: address(res.debt),
            swapData: abi.encode(swapData)
        });

        SwapPath memory swapPath =
            SwapPath({units: swapUnits, recipient: sender, inputAmount: sellAmt, useBalanceOnchain: false});
        uint256 netOut;
        if (isV1) {
            netOut = res.router.sellFtAndXtForV1(sender, res.market, ftAmount, xtAmount, swapPath);
        } else {
            netOut = res.router.sellFtAndXtForV2(sender, res.market, ftAmount, xtAmount, swapPath);
        }
        assertEq(netOut, res.debt.balanceOf(sender));
        assertEq(res.ft.balanceOf(sender), 0);
        assertEq(res.xt.balanceOf(sender), 0);
        assert(maxBurn <= netOut);

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
        uint256 gtId;
        uint256 netXtOut;
        if (isV1) {
            (gtId, netXtOut) = res.router.leverageForV1(sender, res.market, maxLtv, inputPaths, collateralPath);
        } else {
            (gtId, netXtOut) = res.router.leverageForV2(sender, res.market, maxLtv, inputPaths, collateralPath);
        }
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
        (uint256 gtId, uint256 netXtOut) = isV1
            ? res.router.leverageForV1(sender, res.market, maxLtv, inputPaths, collateralPath)
            : res.router.leverageForV2(sender, res.market, maxLtv, inputPaths, collateralPath);
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

        (uint256 gtId,) = isV1
            ? res.router.leverageForV1(sender, res.market, maxLtv, inputPaths, collateralPath)
            : res.router.leverageForV2(sender, res.market, maxLtv, inputPaths, collateralPath);
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
        if (isV1) {
            res.router.leverageForV1(sender, res.market, maxLtv, inputPaths, collateralPath);
        } else {
            res.router.leverageForV2(sender, res.market, maxLtv, inputPaths, collateralPath);
        }

        vm.stopPrank();
    }
}
