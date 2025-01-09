// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanReceiver} from "contracts/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents, OrderErrors} from "contracts/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockFlashLoanReceiver} from "contracts/test/MockFlashLoanReceiver.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import "contracts/storage/TermMaxStorage.sol";

contract OrderTest is Test {
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
        vm.warp(marketConfig.openTime);
        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        res.order = res.market.createOrder(
            maker,
            orderConfig.maxXtReserve,
            ISwapCallback(address(0)),
            orderConfig.curveCuts
        );

        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint amount = 150e8;
        res.debt.mint(deployer, amount);
        res.debt.approve(address(res.market), amount);
        res.market.mint(deployer, amount);
        res.ft.transfer(address(res.order), amount);
        res.xt.transfer(address(res.order), amount);

        vm.stopPrank();
    }

    function testBuyFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.market), underlyingAmtIn);

        uint actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut"));
        uint fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.fee"));
        StateChecker.OrderState memory expectedState = JSONLoader.getOrderStateFromJson(
            testdata,
            ".expected.testBuyFt.contractState"
        );
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.debt,
            res.ft,
            sender,
            sender,
            underlyingAmtIn,
            uint128(actualOut),
            uint128(fee)
        );
        uint256 netOut = res.order.swapExactTokenToToken(res.debt, res.ft, sender, underlyingAmtIn, minTokenOut);

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.ft.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyFtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut"))
        );
        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = expectedNetOut + 1;

        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(res.debt, res.ft, sender, underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSwapTokenWhenTermIsNotOpen() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);
        vm.warp(res.market.config().openTime - 1);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.TermIsNotOpen.selector));
        res.order.swapExactTokenToToken(res.debt, res.ft, sender, underlyingAmtIn, minTokenOut);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.TermIsNotOpen.selector));
        res.order.swapExactTokenToToken(res.debt, res.ft, sender, underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testBuyXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 5e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        uint actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut"));
        uint fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.fee"));
        StateChecker.OrderState memory expectedState = JSONLoader.getOrderStateFromJson(
            testdata,
            ".expected.testBuyXt.contractState"
        );
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.debt,
            res.xt,
            sender,
            sender,
            underlyingAmtIn,
            uint128(actualOut),
            uint128(fee)
        );
        uint256 netOut = res.order.swapExactTokenToToken(res.debt, res.xt, sender, underlyingAmtIn, minTokenOut);

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.xt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyXtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut"))
        );
        uint128 underlyingAmtIn = 5e8;
        uint128 minTokenOut = expectedNetOut + 1;

        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(res.debt, res.xt, sender, underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyFt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.order.swapExactTokenToToken(res.debt, res.ft, sender, underlyingAmtInForBuyFt, minFtOut)
        );
        uint128 minTokenOut = 0e8;
        res.ft.approve(address(res.order), ftAmtIn);

        uint actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut"));
        uint fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.fee"));
        StateChecker.OrderState memory expectedState = JSONLoader.getOrderStateFromJson(
            testdata,
            ".expected.testSellFt.contractState"
        );
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.ft,
            res.debt,
            sender,
            sender,
            ftAmtIn,
            uint128(actualOut),
            uint128(fee)
        );
        uint256 netOut = res.order.swapExactTokenToToken(res.ft, res.debt, sender, ftAmtIn, minTokenOut);

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.ft.balanceOf(sender) == 0);
        assert(res.debt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testSellFtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut"))
        );
        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyFt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.order.swapExactTokenToToken(res.debt, res.ft, sender, underlyingAmtInForBuyFt, minFtOut)
        );
        uint128 minTokenOut = expectedNetOut + 1;

        res.ft.approve(address(res.order), ftAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(res.ft, res.debt, sender, ftAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 5e8;
        uint128 minXTOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyXt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.order.swapExactTokenToToken(res.debt, res.xt, sender, underlyingAmtInForBuyXt, minXTOut)
        );
        uint128 minTokenOut = 0e8;
        res.xt.approve(address(res.order), xtAmtIn);

        uint actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut"));
        uint fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.fee"));
        StateChecker.OrderState memory expectedState = JSONLoader.getOrderStateFromJson(
            testdata,
            ".expected.testSellXt.contractState"
        );
        vm.expectEmit();
        emit OrderEvents.SwapExactTokenToToken(
            res.xt,
            res.debt,
            sender,
            sender,
            xtAmtIn,
            uint128(actualOut),
            uint128(fee)
        );
        uint256 netOut = res.order.swapExactTokenToToken(res.xt, res.debt, sender, xtAmtIn, minTokenOut);

        StateChecker.checkOrderState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.xt.balanceOf(sender) == 0);
        assert(res.debt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testSellXtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut"))
        );
        uint128 underlyingAmtInForBuyXt = 5e8;
        uint128 minXtOut = 0e8;
        res.debt.mint(sender, underlyingAmtInForBuyXt);
        res.debt.approve(address(res.order), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.order.swapExactTokenToToken(res.debt, res.xt, sender, underlyingAmtInForBuyXt, minXtOut)
        );
        uint128 minTokenOut = expectedNetOut + 1;

        res.xt.approve(address(res.order), xtAmtIn);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.UnexpectedAmount.selector, minTokenOut, expectedNetOut));
        res.order.swapExactTokenToToken(res.xt, res.debt, sender, xtAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testBuyExactFt() public {
        vm.startPrank(sender);
        uint128 ftOutAmt = 100e8;
        uint128 maxTokenIn = 100e8;
        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);

        // uint actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut"));
        // uint fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.fee"));
        // StateChecker.OrderState memory expectedState = JSONLoader.getOrderStateFromJson(
        //     testdata,
        //     ".expected.testBuyFt.contractState"
        // );
        // vm.expectEmit();
        // emit OrderEvents.SwapTokenToExactToken(
        //     res.debt,
        //     res.ft,
        //     sender,
        //     sender,
        //     maxTokenIn,
        //     ftOutAmt,
        //     0
        // );
        uint256 netIn = res.order.swapTokenToExactToken(res.debt, res.ft, sender, ftOutAmt, maxTokenIn);

        // StateChecker.checkOrderState(res, expectedState);

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

        // uint actualOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut"));
        // uint fee = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.fee"));
        // StateChecker.OrderState memory expectedState = JSONLoader.getOrderStateFromJson(
        //     testdata,
        //     ".expected.testBuyFt.contractState"
        // );
        // vm.expectEmit();
        // emit OrderEvents.SwapTokenToExactToken(
        //     res.debt,
        //     res.ft,
        //     sender,
        //     sender,
        //     maxTokenIn,
        //     ftOutAmt,
        //     0
        // );
        uint256 netIn = res.order.swapTokenToExactToken(res.debt, res.xt, sender, xtOutAmt, maxTokenIn);

        // StateChecker.checkOrderState(res, expectedState);

        assert(netIn < maxTokenIn);
        assert(res.xt.balanceOf(sender) == xtOutAmt);
        assert(res.debt.balanceOf(sender) == maxTokenIn - netIn);
        vm.stopPrank();
    }

    function testByExactFtWhenTermIsNotOpen() public {
        uint128 ftInAmt = 100e8;
        uint128 maxTokenOut = 100e8;
        res.debt.mint(sender, ftInAmt);
        res.debt.approve(address(res.market), ftInAmt);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.TermIsNotOpen.selector));
        res.order.swapTokenToExactToken(res.debt, res.ft, sender, maxTokenOut, ftInAmt);
    }

    function testUpdateOrderConfig() public {
        vm.startPrank(maker);

        // Prepare new curve cuts
        orderConfig.curveCuts.lendCurveCuts[0].liqSquare++;
        int ftChangeAmt = 1e8;
        int xtChangeAmt = -1e8;

        deal(address(res.ft), maker, ftChangeAmt.toUint256());
        res.ft.approve(address(res.order), ftChangeAmt.toUint256());

        vm.expectEmit();
        emit OrderEvents.UpdateOrder(
            orderConfig.curveCuts,
            ftChangeAmt,
            xtChangeAmt,
            orderConfig.gtId,
            orderConfig.maxXtReserve,
            ISwapCallback(address(0))
        );
        res.order.updateOrder(orderConfig, ftChangeAmt, xtChangeAmt);

        // Verify curve was updated
        OrderConfig memory updatedConfig = res.order.orderConfig();
        assertEq(updatedConfig.curveCuts.lendCurveCuts[0].liqSquare, orderConfig.curveCuts.lendCurveCuts[0].liqSquare);
        assertEq(res.xt.balanceOf(maker), (-xtChangeAmt).toUint256());
        assertEq(res.ft.balanceOf(maker), 0);

        vm.stopPrank();
    }

    function testOnlyMakerCanUpdateOrder() public {
        vm.startPrank(sender);

        vm.expectRevert(OrderErrors.OnlyMaker.selector);
        res.order.updateOrder(orderConfig, 0, 0);

        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.startPrank(maker);

        // Test pause
        res.order.pause();
        assertTrue(TermMaxOrder(address(res.order)).paused());

        // Verify swaps are blocked when paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        res.order.swapExactTokenToToken(res.ft, res.debt, sender, 1e8, 0);

        // Test unpause
        res.order.unpause();
        assertFalse(TermMaxOrder(address(res.order)).paused());

        vm.stopPrank();
    }

    function testOnlyMakerCanPause() public {
        vm.startPrank(sender);

        vm.expectRevert(OrderErrors.OnlyMaker.selector);
        res.order.pause();

        vm.stopPrank();
    }

    function testSwapReverts() public {
        vm.startPrank(sender);

        // Test same token swap
        vm.expectRevert(OrderErrors.CantSwapSameToken.selector);
        res.order.swapExactTokenToToken(res.ft, res.ft, sender, 1e8, 0);

        IERC20 token0 = IERC20(vm.randomAddress());
        IERC20 token1 = IERC20(vm.randomAddress());
        // Test invalid token combination
        vm.expectRevert(abi.encodeWithSelector(OrderErrors.CantNotSwapToken.selector, token0, token1));
        res.order.swapExactTokenToToken(token0, token1, sender, 1e8, 0);

        vm.stopPrank();
    }

    function testSwapWithCallback() public {
        // Deploy mock callback contract
        MockSwapCallback callback = new MockSwapCallback();

        orderConfig.swapTrigger = callback;
        vm.prank(maker);
        res.order.updateOrder(orderConfig, 0, 0);

        vm.startPrank(sender);

        uint128 amountIn = 1e8;
        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.order), amountIn);
        res.order.swapExactTokenToToken(res.debt, res.ft, sender, amountIn, 0);

        uint expectedFtReserve = res.ft.balanceOf(address(res.order));
        assertEq(expectedFtReserve, callback.ftReserve());

        vm.stopPrank();
    }
}

// Mock contracts for testing
contract MockSwapCallback is ISwapCallback {
    uint256 public ftReserve;

    function swapCallback(uint256 ftReserve_) external override {
        ftReserve = ftReserve_;
    }
}
