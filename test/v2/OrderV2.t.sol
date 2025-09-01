// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanReceiver} from "contracts/v1/IFlashLoanReceiver.sol";
import {
    ITermMaxMarketV2, TermMaxMarketV2, Constants, MarketErrors, MarketEvents
} from "contracts/v2/TermMaxMarketV2.sol";
import {
    ITermMaxOrder,
    TermMaxOrderV2,
    ISwapCallback,
    OrderEvents,
    OrderErrors,
    OrderErrorsV2,
    OrderInitialParams
} from "contracts/v2/TermMaxOrderV2.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockFlashLoanReceiver} from "contracts/v1/test/MockFlashLoanReceiver.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {
    VaultInitialParams,
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCut,
    CurveCuts,
    FeeConfig
} from "contracts/v1/storage/TermMaxStorage.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import {DelegateAble} from "contracts/v2/lib/DelegateAble.sol";
import {OrderEventsV2} from "contracts/v2/events/OrderEventsV2.sol";

contract OrderTestV2 is Test {
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

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

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

        vm.stopPrank();
    }

    function testInvalidCurveCuts() public {
        vm.startPrank(maker);
        {
            OrderConfig memory newOrderConfig = orderConfig;
            newOrderConfig.curveCuts.lendCurveCuts[0].offset = 0;
            vm.expectRevert(abi.encodeWithSelector(OrderErrors.InvalidCurveCuts.selector));
            res.order.updateOrder(newOrderConfig, 0, 0);
        }

        {
            OrderConfig memory newOrderConfig = orderConfig;
            newOrderConfig.curveCuts.borrowCurveCuts[0].offset = 0;
            vm.expectRevert(abi.encodeWithSelector(OrderErrors.InvalidCurveCuts.selector));
            res.order.updateOrder(newOrderConfig, 0, 0);
        }

        {
            OrderConfig memory newOrderConfig = orderConfig;
            newOrderConfig.curveCuts.borrowCurveCuts[1].offset = 0;
            vm.expectRevert(abi.encodeWithSelector(OrderErrors.InvalidCurveCuts.selector));
            res.order.updateOrder(newOrderConfig, 0, 0);
        }

        vm.stopPrank();

        vm.prank(maker);
        res.order.updateOrder(orderConfig, 0, 0);
    }

    function testBuyFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        uint256 actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testBuyFt.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.debt, res.ft, sender, sender, underlyingAmtIn, uint128(actualOut), uint128(fee)
        );
        uint256 netOut = res.order.swapExactTokenToToken(
            res.debt, res.ft, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.ft.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyFtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut =
            uint128(vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut")));
        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = expectedNetOut + 1;

        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(
            res.debt, res.ft, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testSwapTokenWhenTermIsNotOpen() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.TermIsNotOpen.selector));
        res.order.swapExactTokenToToken(
            res.debt, res.ft, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testBuyXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 5e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        uint256 actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testBuyXt.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.debt, res.xt, sender, sender, underlyingAmtIn, uint128(actualOut), uint128(fee)
        );
        uint256 netOut = res.order.swapExactTokenToToken(
            res.debt, res.xt, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.xt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyXtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut =
            uint128(vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut")));
        uint128 underlyingAmtIn = 5e8;
        uint128 minTokenOut = expectedNetOut + 1;

        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(
            res.debt, res.xt, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testSellFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyFt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.order.swapExactTokenToToken(
                res.debt, res.ft, sender, underlyingAmtInForBuyFt, minFtOut, block.timestamp + 1 hours
            )
        );
        uint128 minTokenOut = 0e8;
        res.ft.approve(address(res.order), ftAmtIn);

        uint256 actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testSellFt.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.ft, res.debt, sender, sender, ftAmtIn, uint128(actualOut), uint128(fee)
        );
        uint256 netOut =
            res.order.swapExactTokenToToken(res.ft, res.debt, sender, ftAmtIn, minTokenOut, block.timestamp + 1 hours);

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.ft.balanceOf(sender) == 0);
        assert(res.debt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testSellFtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut =
            uint128(vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut")));
        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyFt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.order.swapExactTokenToToken(
                res.debt, res.ft, sender, underlyingAmtInForBuyFt, minFtOut, block.timestamp + 1 hours
            )
        );
        uint128 minTokenOut = expectedNetOut + 1;

        res.ft.approve(address(res.order), ftAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(res.ft, res.debt, sender, ftAmtIn, minTokenOut, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testSellXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 5e8;
        uint128 minXTOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyXt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.order.swapExactTokenToToken(
                res.debt, res.xt, sender, underlyingAmtInForBuyXt, minXTOut, block.timestamp + 1 hours
            )
        );
        uint128 minTokenOut = 0e8;
        res.xt.approve(address(res.order), xtAmtIn);

        uint256 actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testSellXt.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.xt, res.debt, sender, sender, xtAmtIn, uint128(actualOut), uint128(fee)
        );
        uint256 netOut =
            res.order.swapExactTokenToToken(res.xt, res.debt, sender, xtAmtIn, minTokenOut, block.timestamp + 1 hours);

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.xt.balanceOf(sender) == 0);
        assert(res.debt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testSellXtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut =
            uint128(vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut")));
        uint128 underlyingAmtInForBuyXt = 5e8;
        uint128 minXtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyXt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.order.swapExactTokenToToken(
                res.debt, res.xt, sender, underlyingAmtInForBuyXt, minXtOut, block.timestamp + 1 hours
            )
        );
        uint128 minTokenOut = expectedNetOut + 1;

        res.xt.approve(address(res.order), xtAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(res.xt, res.debt, sender, xtAmtIn, minTokenOut, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testBuyExactFt() public {
        vm.startPrank(sender);
        uint128 ftOutAmt = 100e8;
        uint128 maxTokenIn = 100e8;
        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);

        uint256 actualIn = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyExactFt.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyExactFt.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testBuyExactFt.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapTokenToExactToken(
            res.debt, res.ft, sender, sender, ftOutAmt, uint128(actualIn), uint128(fee)
        );
        uint256 netIn =
            res.order.swapTokenToExactToken(res.debt, res.ft, sender, ftOutAmt, maxTokenIn, block.timestamp + 1 hours);

        StateChecker.checkOrderState(res, expectedState);

        assert(netIn < maxTokenIn);
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.debt.balanceOf(sender) == maxTokenIn - netIn);

        vm.stopPrank();
    }

    function testBuyExactXt() public {
        vm.startPrank(sender);
        uint128 xtOutAmt = 100e8;
        uint128 maxTokenIn = 100e8;
        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);

        uint256 actualIn = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyExactXt.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyExactXt.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testBuyExactXt.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapTokenToExactToken(
            res.debt, res.xt, sender, sender, xtOutAmt, uint128(actualIn), uint128(fee)
        );
        uint256 netIn =
            res.order.swapTokenToExactToken(res.debt, res.xt, sender, xtOutAmt, maxTokenIn, block.timestamp + 1 hours);

        StateChecker.checkOrderState(res, expectedState);

        assert(netIn < maxTokenIn);
        assert(res.xt.balanceOf(sender) == xtOutAmt);
        assert(res.debt.balanceOf(sender) == maxTokenIn - netIn);
        vm.stopPrank();
    }

    function testSellFtForExactToken() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyFt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyFt);
        uint128 maxTokenIn = uint128(
            res.order.swapExactTokenToToken(
                res.debt, res.ft, sender, underlyingAmtInForBuyFt, minFtOut, block.timestamp + 1 hours
            )
        );
        uint128 debtOutAmt = 80e8;
        res.ft.approve(address(res.order), maxTokenIn);

        uint256 actualIn = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFtForExactToken.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFtForExactToken.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testSellFtForExactToken.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapTokenToExactToken(
            res.ft, res.debt, sender, sender, debtOutAmt, uint128(actualIn), uint128(fee)
        );
        uint256 netIn =
            res.order.swapTokenToExactToken(res.ft, res.debt, sender, debtOutAmt, maxTokenIn, block.timestamp + 1 hours);

        StateChecker.checkOrderState(res, expectedState);

        assert(netIn < maxTokenIn);
        assert(res.debt.balanceOf(sender) == debtOutAmt);
        assert(res.ft.balanceOf(sender) == maxTokenIn - netIn);

        vm.stopPrank();
    }

    function testSellXtForExactToken() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 5e8;
        uint128 minFtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyXt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyXt);
        uint128 maxTokenIn = uint128(
            res.order.swapExactTokenToToken(
                res.debt, res.xt, sender, underlyingAmtInForBuyXt, minFtOut, block.timestamp + 1 hours
            )
        );
        uint128 debtOutAmt = 3e8;
        res.xt.approve(address(res.order), maxTokenIn);

        uint256 actualIn = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXtForExactToken.output.netOut"));
        uint256 fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXtForExactToken.output.fee"));
        StateChecker.OrderState memory expectedState =
            JSONLoader.getOrderStateFromJson(testdata, ".expected.testSellXtForExactToken.contractState");
        vm.expectEmit();
        emit OrderEvents.SwapTokenToExactToken(
            res.xt, res.debt, sender, sender, debtOutAmt, uint128(actualIn), uint128(fee)
        );
        uint256 netIn =
            res.order.swapTokenToExactToken(res.xt, res.debt, sender, debtOutAmt, maxTokenIn, block.timestamp + 1 hours);

        StateChecker.checkOrderState(res, expectedState);

        assert(netIn < maxTokenIn);
        assert(res.debt.balanceOf(sender) == debtOutAmt);
        assert(res.xt.balanceOf(sender) == maxTokenIn - netIn);

        vm.stopPrank();
    }

    function testByExactFtWhenTermIsNotOpen() public {
        uint128 ftInAmt = 100e8;
        uint128 maxTokenOut = 100e8;
        res.debt.mint(sender, ftInAmt);
        res.debt.approve(address(res.market), ftInAmt);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(abi.encodeWithSignature("TermIsNotOpen()"));
        res.order.swapTokenToExactToken(res.debt, res.ft, sender, maxTokenOut, ftInAmt, block.timestamp + 1 hours);
    }

    function testIssueFtWhenSwap() public {
        vm.startPrank(maker);
        // Mint a GT
        (uint256 gtId,) = LoanUtils.fastMintGt(res, maker, 100e8, 1e18);
        DelegateAble(address(res.gt)).setDelegate(address(res.order), true);
        orderConfig.gtId = gtId;
        res.order.updateOrder(orderConfig, -150e8, 0);
        vm.stopPrank();

        uint128 ftOutAmt = 151e8;
        uint128 maxTokenIn = 150e8;
        vm.startPrank(sender);
        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);
        res.order.swapTokenToExactToken(res.debt, res.ft, sender, ftOutAmt, maxTokenIn, block.timestamp + 1 hours);
        assertEq(res.ft.balanceOf(sender), ftOutAmt);
        (, uint128 debtAmt,) = res.gt.loanInfo(gtId);
        assertGt(debtAmt, 100e8);
        vm.stopPrank();
    }

    function testIssueFtWhenNoAssets() public {
        vm.startPrank(maker);
        // Mint a GT
        (uint256 gtId,) = LoanUtils.fastMintGt(res, maker, 100e8, 1e18);
        DelegateAble(address(res.gt)).setDelegate(address(res.order), true);

        orderConfig.gtId = gtId;
        res.order.updateOrder(orderConfig, -150e8, -150e8);
        assert(res.ft.balanceOf(address(res.order)) == 0);
        assert(res.xt.balanceOf(address(res.order)) == 0);
        vm.stopPrank();

        uint128 ftOutAmt = 151e8;
        uint128 maxTokenIn = 150e8;
        vm.startPrank(sender);
        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);
        res.order.swapTokenToExactToken(res.debt, res.ft, sender, ftOutAmt, maxTokenIn, block.timestamp + 1 hours);
        assertEq(res.ft.balanceOf(sender), ftOutAmt);
        (, uint128 debtAmt,) = res.gt.loanInfo(gtId);
        assertGt(debtAmt, 100e8);
        vm.stopPrank();
    }

    function testRevertWhenIssueFt() public {
        vm.prank(maker);
        res.order.updateOrder(orderConfig, -150e8, 0);

        uint128 ftOutAmt = 151e8;
        uint128 maxTokenIn = 150e8;
        vm.startPrank(sender);

        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);
        vm.expectRevert();
        res.order.swapTokenToExactToken(res.debt, res.ft, sender, ftOutAmt, maxTokenIn, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function testUpdateOrderConfig() public {
        vm.startPrank(maker);

        // Prepare new curve cuts
        OrderConfig memory newOrderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".newOrderConfig");
        int256 ftChangeAmt = 1e8;
        int256 xtChangeAmt = -1e8;

        deal(address(res.ft), maker, ftChangeAmt.toUint256());
        res.ft.approve(address(res.order), ftChangeAmt.toUint256());

        // Expect UpdateOrder event
        vm.expectEmit();
        emit OrderEvents.UpdateOrder(
            newOrderConfig.curveCuts,
            ftChangeAmt,
            xtChangeAmt,
            newOrderConfig.gtId,
            newOrderConfig.maxXtReserve,
            newOrderConfig.swapTrigger
        );
        res.order.updateOrder(newOrderConfig, ftChangeAmt, xtChangeAmt);

        // Verify curve was updated
        OrderConfig memory updatedConfig = res.order.orderConfig();
        for (uint256 i = 0; i < updatedConfig.curveCuts.lendCurveCuts.length; i++) {
            assertEq(
                updatedConfig.curveCuts.lendCurveCuts[i].xtReserve, newOrderConfig.curveCuts.lendCurveCuts[i].xtReserve
            );
            assertEq(
                updatedConfig.curveCuts.lendCurveCuts[i].liqSquare, newOrderConfig.curveCuts.lendCurveCuts[i].liqSquare
            );
            assertEq(updatedConfig.curveCuts.lendCurveCuts[i].offset, newOrderConfig.curveCuts.lendCurveCuts[i].offset);
        }
        for (uint256 i = 0; i < updatedConfig.curveCuts.borrowCurveCuts.length; i++) {
            assertEq(
                updatedConfig.curveCuts.borrowCurveCuts[i].xtReserve,
                newOrderConfig.curveCuts.borrowCurveCuts[i].xtReserve
            );
            assertEq(
                updatedConfig.curveCuts.borrowCurveCuts[i].liqSquare,
                newOrderConfig.curveCuts.borrowCurveCuts[i].liqSquare
            );
            assertEq(
                updatedConfig.curveCuts.borrowCurveCuts[i].offset, newOrderConfig.curveCuts.borrowCurveCuts[i].offset
            );
        }
        assertEq(res.xt.balanceOf(maker), (-xtChangeAmt).toUint256());
        assertEq(res.ft.balanceOf(maker), 0);

        vm.stopPrank();
    }

    function testOnlyMakerCanUpdateOrder() public {
        vm.startPrank(sender);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", sender));
        res.order.updateOrder(orderConfig, 0, 0);

        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.startPrank(maker);

        // Test pause
        res.order.pause();
        assertTrue(TermMaxOrderV2(address(res.order)).paused());

        // Verify swaps are blocked when paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        res.order.swapExactTokenToToken(res.ft, res.debt, sender, 1e8, 0, block.timestamp + 1 hours);

        // Test unpause
        res.order.unpause();
        assertFalse(TermMaxOrderV2(address(res.order)).paused());

        vm.stopPrank();
    }

    function testOnlyMakerCanPause() public {
        vm.startPrank(sender);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", sender));
        res.order.pause();

        vm.stopPrank();
    }

    function testSwapReverts() public {
        vm.startPrank(sender);

        // Test same token swap
        vm.expectRevert(OrderErrors.CantSwapSameToken.selector);
        res.order.swapExactTokenToToken(res.ft, res.ft, sender, 1e8, 0, block.timestamp + 1 hours);

        IERC20 token0 = IERC20(vm.randomAddress());
        IERC20 token1 = IERC20(vm.randomAddress());
        // Test invalid token combination
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.CantNotSwapToken.selector, token0, token1));
        res.order.swapExactTokenToToken(token0, token1, sender, 1e8, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    function testSwapWithCallback(uint128 swapAmt, bool isBuy, bool isFt) public {
        vm.assume(swapAmt > 0 && swapAmt < 0.1e8);

        // Deploy mock callback contract
        MockSwapCallback callback = new MockSwapCallback();

        orderConfig.swapTrigger = callback;
        vm.startPrank(maker);
        res.order.updateOrder(orderConfig, 0, 0);

        res.debt.mint(maker, 150e8);
        res.debt.approve(address(res.market), 150e8);
        res.market.mint(address(res.order), 150e8);
        vm.stopPrank();

        vm.startPrank(sender);

        res.debt.mint(sender, swapAmt * 2);

        res.debt.approve(address(res.order), swapAmt);
        res.debt.approve(address(res.market), swapAmt);
        res.market.mint(sender, swapAmt);

        IERC20 tokenIn;
        IERC20 tokenOut;

        if (isBuy && isFt) {
            tokenIn = res.debt;
            tokenOut = res.ft;
        }

        if (isBuy && !isFt) {
            tokenIn = res.debt;
            tokenOut = res.xt;
        }

        if (!isBuy && isFt) {
            tokenIn = res.ft;
            tokenOut = res.debt;
        }

        if (!isBuy && !isFt) {
            tokenIn = res.xt;
            tokenOut = res.debt;
        }
        uint256 ftBalanceBefore = res.ft.balanceOf(address(res.order));
        uint256 xtBalanceBefore = res.xt.balanceOf(address(res.order));
        tokenIn.approve(address(res.order), swapAmt);
        res.order.swapExactTokenToToken(tokenIn, tokenOut, sender, swapAmt, 0, block.timestamp + 1 hours);

        uint256 ftBalanceAfter = res.ft.balanceOf(address(res.order));
        uint256 xtBalanceAfter = res.xt.balanceOf(address(res.order));

        assertEq(ftBalanceBefore.toInt256() + callback.deltaFt(), ftBalanceAfter.toInt256());
        assertEq(xtBalanceBefore.toInt256() + callback.deltaXt(), xtBalanceAfter.toInt256());

        vm.stopPrank();
    }

    function testUpdateOrderFeeRate() public {
        // Create new fee config
        FeeConfig memory newFeeConfig = marketConfig.feeConfig;
        newFeeConfig.lendTakerFeeRatio++;
        newFeeConfig.borrowTakerFeeRatio++;

        // Test that non-owner cannot update fee rate
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.OnlyMarket.selector));
        vm.prank(sender);
        res.order.updateFeeConfig(newFeeConfig);

        // Test that owner can update fee rate
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(OrderErrorsV2.FeeConfigCanNotBeUpdated.selector));
        res.market.updateOrderFeeRate(res.order, newFeeConfig);
        vm.stopPrank();
    }

    function testRevertLendIsNotAllowed() public {
        vm.startPrank(maker);
        OrderConfig memory testOrderConfig = res.order.orderConfig();
        testOrderConfig.curveCuts.borrowCurveCuts = new CurveCut[](0);

        vm.expectEmit();
        emit OrderEvents.UpdateOrder(
            testOrderConfig.curveCuts,
            0,
            0,
            testOrderConfig.gtId,
            testOrderConfig.maxXtReserve,
            ISwapCallback(address(0))
        );
        res.order.updateOrder(testOrderConfig, 0, 0);
        vm.stopPrank();

        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        vm.expectRevert(abi.encodeWithSelector(OrderErrors.LendIsNotAllowed.selector));
        res.order.swapExactTokenToToken(
            res.debt, res.ft, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testRevertBorrowIsNotAllowed() public {
        vm.startPrank(maker);
        OrderConfig memory testOrderConfig = res.order.orderConfig();
        testOrderConfig.curveCuts.lendCurveCuts = new CurveCut[](0);

        vm.expectEmit();
        emit OrderEvents.UpdateOrder(
            testOrderConfig.curveCuts,
            0,
            0,
            testOrderConfig.gtId,
            testOrderConfig.maxXtReserve,
            ISwapCallback(address(0))
        );
        res.order.updateOrder(testOrderConfig, 0, 0);
        vm.stopPrank();

        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        vm.expectRevert(abi.encodeWithSelector(OrderErrors.BorrowIsNotAllowed.selector));
        res.order.swapExactTokenToToken(
            res.debt, res.xt, sender, underlyingAmtIn, minTokenOut, block.timestamp + 1 hours
        );

        vm.stopPrank();
    }

    function testUtWhenDeadlineLessThanBlockTime() public {
        vm.startPrank(sender);

        uint128 swapAmt = 5e8;
        IERC20 tokenIn = IERC20(address(res.debt));
        IERC20 tokenOut = IERC20(address(res.xt));

        // Set block timestamp
        uint256 currentTime = 1000;
        vm.warp(currentTime);

        // Try to swap with deadline less than block time
        uint256 pastDeadline = currentTime - 1;

        tokenIn.approve(address(res.order), swapAmt);

        vm.expectRevert(OrderErrors.DeadlineExpired.selector);
        res.order.swapExactTokenToToken(tokenIn, tokenOut, sender, swapAmt, 0, pastDeadline);

        vm.expectRevert(OrderErrors.DeadlineExpired.selector);
        res.order.swapTokenToExactToken(tokenIn, tokenOut, sender, 1, swapAmt, pastDeadline);

        vm.stopPrank();
    }

    function testAprWithoutCurve() public {
        vm.startPrank(maker);
        OrderConfig memory testOrderConfig = res.order.orderConfig();
        testOrderConfig.curveCuts.lendCurveCuts = new CurveCut[](0);
        testOrderConfig.curveCuts.borrowCurveCuts = new CurveCut[](0);

        vm.expectEmit();
        emit OrderEvents.UpdateOrder(
            testOrderConfig.curveCuts,
            0,
            0,
            testOrderConfig.gtId,
            testOrderConfig.maxXtReserve,
            ISwapCallback(address(0))
        );
        res.order.updateOrder(testOrderConfig, 0, 0);
        vm.stopPrank();

        (uint256 lendApr, uint256 borrowApr) = res.order.apr();

        assert(lendApr == 0);
        assert(borrowApr == type(uint256).max);
    }

    function testAprWithCurve() public {
        vm.startPrank(maker);
        OrderConfig memory testOrderConfig = res.order.orderConfig();
        testOrderConfig.curveCuts.lendCurveCuts = new CurveCut[](0);

        res.order.updateOrder(testOrderConfig, 0, 0);

        (uint256 lendApr, uint256 borrowApr) = res.order.apr();

        assert(lendApr == 0);

        testOrderConfig = res.order.orderConfig();
        testOrderConfig.curveCuts.borrowCurveCuts = new CurveCut[](0);
        res.order.updateOrder(testOrderConfig, 0, 0);

        (lendApr, borrowApr) = res.order.apr();

        assert(borrowApr == type(uint256).max);

        vm.stopPrank();
    }

    function testSetGeneralConfig(
        uint256 newGtId,
        uint256 newMaxXtReserve,
        ISwapCallback newTrigger,
        uint256 newVirtualXtReserve
    ) public {
        vm.startPrank(maker);

        // Expect GeneralConfigUpdated event
        vm.expectEmit();
        emit OrderEventsV2.GeneralConfigUpdated(newGtId, newMaxXtReserve, newTrigger, newVirtualXtReserve);
        res.order.setGeneralConfig(newGtId, newMaxXtReserve, newTrigger, newVirtualXtReserve);

        // Verify the configuration was updated
        OrderConfig memory updatedConfig = res.order.orderConfig();
        assertEq(updatedConfig.gtId, newGtId, "GT ID should match");
        assertEq(updatedConfig.maxXtReserve, newMaxXtReserve, "Max XT reserve should match");
        assertEq(address(updatedConfig.swapTrigger), address(newTrigger), "Swap trigger should match");
        assertEq(res.order.virtualXtReserve(), newVirtualXtReserve, "Virtual XT reserve should match");

        vm.stopPrank();
    }

    function testSetGeneralConfigOnlyMaker() public {
        vm.startPrank(sender);

        uint256 newGtId = 12345;
        uint256 newMaxXtReserve = 200e8;
        ISwapCallback newTrigger = ISwapCallback(address(0));
        uint256 newVirtualXtReserve = 180e8;

        // Test that non-maker cannot update
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", sender));
        res.order.setGeneralConfig(newGtId, newMaxXtReserve, newTrigger, newVirtualXtReserve);

        vm.stopPrank();
    }

    function testSetPool() public {
        vm.startPrank(maker);

        uint256 amount = res.ft.balanceOf(address(res.order));
        MockERC4626 pool = new MockERC4626(res.debt);
        vm.expectEmit();
        emit OrderEventsV2.PoolUpdated(address(pool));
        res.order.setPool(pool);
        assertEq(address(res.order.pool()), address(pool), "Pool should match");
        assertEq(res.debt.balanceOf(address(res.order)), 0, "Order should have no debt balance");
        assertEq(res.ft.balanceOf(address(res.order)), 0, "Order should have no FT balance");
        assertEq(res.xt.balanceOf(address(res.order)), 0, "Order should have no XT balance");
        assertEq(pool.balanceOf(address(res.order)), amount, "Order should have pool shares");
        assertEq(res.debt.balanceOf(address(pool)), amount, "Pool should have debt balance");

        MockERC4626 newPool = new MockERC4626(res.debt);
        vm.expectEmit();
        emit OrderEventsV2.PoolUpdated(address(newPool));
        res.order.setPool(newPool);
        assertEq(address(res.order.pool()), address(newPool), "New Pool should match");
        assertEq(res.debt.balanceOf(address(res.order)), 0, "Order should have no debt balance");
        assertEq(res.ft.balanceOf(address(res.order)), 0, "Order should have no FT balance");
        assertEq(res.xt.balanceOf(address(res.order)), 0, "Order should have no XT balance");
        assertEq(newPool.balanceOf(address(res.order)), amount, "Order should have new pool shares");
        assertEq(res.debt.balanceOf(address(newPool)), amount, "Pool should have debt balance");

        vm.expectEmit();
        emit OrderEventsV2.PoolUpdated(address(0));
        res.order.setPool(MockERC4626(address(0)));
        // Verify the pool was set to zero address
        assertEq(address(res.order.pool()), address(0), "Pool should be zero address");
        assertEq(res.ft.balanceOf(address(res.order)), amount, "Order should have FT balance");
        assertEq(res.xt.balanceOf(address(res.order)), amount, "Order should have XT balance");
        assertEq(res.debt.balanceOf(address(res.order)), 0, "Order should have no debt balance");
        assertEq(pool.balanceOf(address(res.order)), 0, "Order should have no pool shares");
        assertEq(newPool.balanceOf(address(res.order)), 0, "Order should have no new pool shares");
        vm.stopPrank();
    }

    function testSetCurve() public {
        vm.startPrank(maker);

        OrderConfig memory newOrderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".newOrderConfig");

        // Create new curve cuts
        CurveCuts memory newCurveCuts = newOrderConfig.curveCuts;

        res.order.setCurve(newCurveCuts);

        // Verify the curve was updated
        OrderConfig memory updatedConfig = res.order.orderConfig();

        // Check lend curve cuts
        for (uint256 i = 0; i < updatedConfig.curveCuts.lendCurveCuts.length; i++) {
            assertEq(
                updatedConfig.curveCuts.lendCurveCuts[i].xtReserve,
                newCurveCuts.lendCurveCuts[i].xtReserve,
                "Lend curve XT reserve should match"
            );
            assertEq(
                updatedConfig.curveCuts.lendCurveCuts[i].liqSquare,
                newCurveCuts.lendCurveCuts[i].liqSquare,
                "Lend curve liq square should match"
            );
            assertEq(
                updatedConfig.curveCuts.lendCurveCuts[i].offset,
                newCurveCuts.lendCurveCuts[i].offset,
                "Lend curve offset should match"
            );
        }

        // Check borrow curve cuts
        for (uint256 i = 0; i < updatedConfig.curveCuts.borrowCurveCuts.length; i++) {
            assertEq(
                updatedConfig.curveCuts.borrowCurveCuts[i].xtReserve,
                newCurveCuts.borrowCurveCuts[i].xtReserve,
                "Borrow curve XT reserve should match"
            );
            assertEq(
                updatedConfig.curveCuts.borrowCurveCuts[i].liqSquare,
                newCurveCuts.borrowCurveCuts[i].liqSquare,
                "Borrow curve liq square should match"
            );
            assertEq(
                updatedConfig.curveCuts.borrowCurveCuts[i].offset,
                newCurveCuts.borrowCurveCuts[i].offset,
                "Borrow curve offset should match"
            );
        }

        vm.stopPrank();

        // Test that non-maker cannot set curve
        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", sender));
        res.order.setCurve(newCurveCuts);
        vm.stopPrank();

        // Test invalid curve cuts
        vm.startPrank(maker);
        CurveCuts memory invalidCurveCuts = newCurveCuts;
        invalidCurveCuts.lendCurveCuts[0].offset = 0;
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.InvalidCurveCuts.selector));
        res.order.setCurve(invalidCurveCuts);
        vm.stopPrank();
    }

    function testAddLiquidity() public {
        vm.startPrank(maker);
        uint256 ftBalanceBefore = res.ft.balanceOf(address(res.order));
        uint256 xtBalanceBefore = res.xt.balanceOf(address(res.order));

        uint256 addedAmt = 100e8;
        res.debt.mint(maker, addedAmt);
        res.debt.approve(address(res.order), addedAmt);
        res.order.addLiquidity(res.debt, addedAmt);
        uint256 ftBalanceAfter = res.ft.balanceOf(address(res.order));
        uint256 xtBalanceAfter = res.xt.balanceOf(address(res.order));
        assertEq(ftBalanceAfter, ftBalanceBefore + addedAmt, "FT balance should increase by added amount");
        assertEq(xtBalanceAfter, xtBalanceBefore + addedAmt, "XT balance should increase by added amount");

        MockERC4626 pool = new MockERC4626(res.debt);
        res.order.setPool(pool);

        res.debt.mint(maker, addedAmt);
        res.debt.approve(address(res.order), addedAmt);
        res.order.addLiquidity(res.debt, addedAmt);

        assertEq(pool.balanceOf(address(res.order)), addedAmt * 2 + 150e8, "Pool shares should match added amount");
        assertEq(res.debt.balanceOf(address(pool)), addedAmt * 2 + 150e8, "Pool should have debt balance");

        res.debt.mint(maker, addedAmt);
        res.debt.approve(address(pool), addedAmt);
        pool.deposit(addedAmt, maker);
        pool.approve(address(res.order), addedAmt);
        res.order.addLiquidity(pool, addedAmt);

        assertEq(pool.balanceOf(address(res.order)), addedAmt * 3 + 150e8, "Pool shares should match added amount");
        assertEq(res.debt.balanceOf(address(pool)), addedAmt * 3 + 150e8, "Pool should have debt balance");

        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        vm.startPrank(maker);
        uint256 ftBalanceBefore = res.ft.balanceOf(address(res.order));
        uint256 xtBalanceBefore = res.xt.balanceOf(address(res.order));

        uint256 removedAmt = 100e8;
        res.order.removeLiquidity(res.debt, removedAmt, maker);
        uint256 ftBalanceAfter = res.ft.balanceOf(address(res.order));
        uint256 xtBalanceAfter = res.xt.balanceOf(address(res.order));
        assertEq(ftBalanceAfter, ftBalanceBefore - removedAmt, "FT balance should decrease by removed amount");
        assertEq(xtBalanceAfter, xtBalanceBefore - removedAmt, "XT balance should decrease by removed amount");

        removedAmt = 10e8;
        MockERC4626 pool = new MockERC4626(res.debt);
        res.order.setPool(pool);

        res.order.removeLiquidity(pool, removedAmt, maker);
        assertEq(pool.balanceOf(address(res.order)), 50e8 - removedAmt, "Pool shares should match removed amount");
        assertEq(pool.balanceOf(address(maker)), removedAmt, "Maker should receive removed shares");

        res.order.removeLiquidity(res.debt, removedAmt, maker);
        assertEq(pool.balanceOf(address(res.order)), 50e8 - removedAmt * 2, "Pool shares should match removed amount");
        assertEq(pool.balanceOf(address(maker)), removedAmt, "Maker should receive no shares");
        assertEq(res.debt.balanceOf(address(maker)), removedAmt + 100e8, "Maker should receive removed debt");
        vm.stopPrank();
    }

    function testFuzz_withdrawAllAssetsBeforeMaturity(
        bool withPool,
        uint128 addDebtToPool,
        uint128 addFt,
        uint128 addXt,
        address recipient
    ) public {
        // recipient cannot be zero or the order itself (would re-credit FT/XT back to order)
        vm.assume(recipient != address(0) && recipient != address(res.order));

        // Bound fuzzed amounts to reasonable ranges
        addDebtToPool = uint128(bound(addDebtToPool, 0, 1_000e8));
        addFt = uint128(bound(addFt, 0, 1_000e8));
        addXt = uint128(bound(addXt, 0, 1_000e8));

        // Optionally set pool and pre-load additional debt liquidity
        MockERC4626 pool;
        vm.startPrank(maker);
        if (withPool) {
            pool = new MockERC4626(res.debt);
            res.order.setPool(pool);

            if (addDebtToPool > 0) {
                // Fund maker with debt and deposit via order into pool
                res.debt.mint(maker, addDebtToPool);
                res.debt.approve(address(res.order), addDebtToPool);
                res.order.addLiquidity(res.debt, addDebtToPool);
            }
        }

        // Optionally leave residual FT on order
        if (addFt > 0) {
            // Mint FT/XT to maker, then transfer only FT to the order
            res.debt.mint(maker, addFt);
            res.debt.approve(address(res.market), addFt);
            res.market.mint(maker, addFt);
            res.ft.transfer(address(res.order), addFt);
        }

        // Optionally leave residual XT on order
        if (addXt > 0) {
            res.debt.mint(maker, addXt);
            res.debt.approve(address(res.market), addXt);
            res.market.mint(maker, addXt);
            res.xt.transfer(address(res.order), addXt);
        }
        vm.stopPrank();

        // Snapshot pre-state
        uint256 debtBefore = res.debt.balanceOf(recipient);
        uint256 ftBefore = res.ft.balanceOf(recipient);
        uint256 xtBefore = res.xt.balanceOf(recipient);

        uint256 poolSharesBefore = 0;
        if (withPool) {
            poolSharesBefore = pool.balanceOf(address(res.order));
        }

        // Compute expected event values
        uint256 orderFtBefore = res.ft.balanceOf(address(res.order));
        uint256 orderXtBefore = res.xt.balanceOf(address(res.order));
        uint256 maxBurned = orderFtBefore < orderXtBefore ? orderFtBefore : orderXtBefore;
        uint256 expectedDebtTokenEvent = (withPool ? poolSharesBefore : 0) + maxBurned;
        uint256 expectedFtEvent = orderFtBefore - maxBurned;
        uint256 expectedXtEvent = orderXtBefore - maxBurned;

        // Expect event
        vm.expectEmit();
        emit OrderEventsV2.RedeemedAllBeforeMaturity(
            recipient, expectedDebtTokenEvent, expectedFtEvent, expectedXtEvent
        );

        // Execute withdrawal as owner
        vm.startPrank(maker);
        (uint256 debtTokenAmount, uint256 ftAmount, uint256 xtAmount) =
            res.order.withdrawAllAssetsBeforeMaturity(recipient);
        vm.stopPrank();

        // Validate recipient received exactly the returned amounts
        assertEq(res.debt.balanceOf(recipient) - debtBefore, debtTokenAmount, "Debt received mismatch");
        assertEq(res.ft.balanceOf(recipient) - ftBefore, ftAmount, "FT received mismatch");
        assertEq(res.xt.balanceOf(recipient) - xtBefore, xtAmount, "XT received mismatch");

        // Order should hold no FT/XT after operation
        assertEq(res.ft.balanceOf(address(res.order)), 0, "Order FT should be zero");
        assertEq(res.xt.balanceOf(address(res.order)), 0, "Order XT should be zero");

        // If pool was set, all shares should be redeemed
        if (withPool) {
            assertEq(pool.balanceOf(address(res.order)), 0, "Order pool shares should be zero");
            // Redeem should align with returned debt token amount (MockERC4626 is 1:1)
            uint256 expectedFromPool = poolSharesBefore; // 1:1 shares->assets in MockERC4626
            assertEq(debtTokenAmount, expectedFromPool, "Debt from pool mismatch");
        } else {
            assertEq(debtTokenAmount, 0, "Debt from pool should be zero when pool unset");
        }
    }

    function testBorrowToken_SufficientBalances() public {
        address recipient = vm.randomAddress();
        uint256 amount = 10e8;

        // Pre-state
        uint256 orderFtBefore = res.ft.balanceOf(address(res.order));
        uint256 orderXtBefore = res.xt.balanceOf(address(res.order));
        uint256 recipientDebtBefore = res.debt.balanceOf(recipient);

        vm.startPrank(maker);
        vm.expectEmit();
        emit OrderEventsV2.Borrowed(recipient, amount);
        res.order.borrowToken(recipient, amount);
        vm.stopPrank();

        // Recipient should receive debt tokens
        assertEq(res.debt.balanceOf(recipient), recipientDebtBefore + amount, "recipient debt incorrect");
        // Order FT/XT should decrease by amount (no issuance path here)
        assertEq(res.ft.balanceOf(address(res.order)), orderFtBefore - amount, "order FT decreased");
        assertEq(res.xt.balanceOf(address(res.order)), orderXtBefore - amount, "order XT decreased");
    }

    function testBorrowToken_IssueFtFromGt() public {
        address recipient = vm.randomAddress();

        // Prepare GT and delegate to order so it can issue FT
        vm.startPrank(maker);
        (uint256 gtId,) = LoanUtils.fastMintGt(res, maker, 100e8, 1e18);
        DelegateAble(address(res.gt)).setDelegate(address(res.order), true);

        // Update order to use this gtId and reduce FT so FT < amount while XT >= amount
        OrderConfig memory cfg = orderConfig;
        cfg.gtId = gtId;
        // Reduce FT by 70e8 so FT becomes 80e8 (given initial 150e8), keep XT unchanged (150e8)
        res.order.updateOrder(cfg, -70e8, 0);

        // Track GT debt before
        (, uint128 debtBefore,) = res.gt.loanInfo(gtId);

        uint256 amount = 120e8; // requires issuing 40e8 FT
        uint256 recipientDebtBefore = res.debt.balanceOf(recipient);
        uint256 xtBefore = res.xt.balanceOf(address(res.order));

        vm.expectEmit();
        emit OrderEventsV2.Borrowed(recipient, amount);
        res.order.borrowToken(recipient, amount);
        vm.stopPrank();

        // Recipient debt increased by amount
        assertEq(res.debt.balanceOf(recipient), recipientDebtBefore + amount, "recipient debt incorrect");
        // XT decreased by amount
        assertEq(res.xt.balanceOf(address(res.order)), xtBefore - amount, "XT should decrease by amount");
        // GT debt increased due to issuing FT
        (, uint128 debtAfter,) = res.gt.loanInfo(gtId);
        assertGt(debtAfter, debtBefore, "GT debt should increase");
    }

    function testBorrowToken_RevertWhenInsufficientXT() public {
        address recipient = vm.randomAddress();

        // Prepare GT so issuance path is available (but XT will be limiting)
        vm.startPrank(maker);
        (uint256 gtId,) = LoanUtils.fastMintGt(res, maker, 100e8, 1e18);
        DelegateAble(address(res.gt)).setDelegate(address(res.order), true);
        OrderConfig memory cfg = orderConfig;
        cfg.gtId = gtId;
        // Reduce XT aggressively so xt < amount while FT remains high
        // XT goes from 150e8 to 30e8
        res.order.updateOrder(cfg, 0, -120e8);

        uint256 amount = 60e8; // > xt, should revert when burning
        vm.expectRevert();
        res.order.borrowToken(recipient, amount);
        vm.stopPrank();
    }

    function testBorrowToken_OnlyOwner() public {
        address recipient = vm.randomAddress();
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", sender));
        res.order.borrowToken(recipient, 1e8);
    }
}

// Mock contracts for testing
contract MockSwapCallback is ISwapCallback {
    int256 public deltaFt;
    int256 public deltaXt;

    function afterSwap(uint256, uint256, int256 deltaFt_, int256 deltaXt_) external override {
        deltaFt = deltaFt_;
        deltaXt = deltaXt_;
    }
}
