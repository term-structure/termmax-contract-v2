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

contract OrderTestV2WithPool is Test {
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

    MockERC4626 pool;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        res = DeployUtils.deployMarket(deployer, marketConfig, maxLtv, liquidationLtv);

        pool = new MockERC4626(res.debt);

        OrderInitialParams memory orderParams;
        orderParams.pool = pool;
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
        res.debt.approve(address(pool), amount);
        pool.deposit(amount, address(res.order));

        vm.stopPrank();
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
        // Increase the pool shares's value
        res.debt.mint(address(pool), underlyingAmtIn);
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

    function testBuyXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 5e8;
        uint128 minTokenOut = 0e8;
        res.debt.mint(sender, underlyingAmtIn);
        res.debt.approve(address(res.order), underlyingAmtIn);

        // Increase the pool shares's value
        res.debt.mint(address(pool), underlyingAmtIn);

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

    function testIssueFtWhenSwap() public {
        vm.startPrank(maker);
        // Mint a GT
        (uint256 gtId,) = LoanUtils.fastMintGt(res, maker, 100e8, 1e18);
        DelegateAble(address(res.gt)).setDelegate(address(res.order), true);
        orderConfig.gtId = gtId;
        res.order.setGeneralConfig(orderConfig.gtId, orderConfig.swapTrigger);
        res.order.withdrawAssets(pool, maker, 150e8);
        vm.stopPrank();

        // Inscrease the pool shares's value
        res.debt.mint(address(pool), 10e8);

        uint128 ftOutAmt = 161e8;
        uint128 maxTokenIn = 160e8;
        vm.startPrank(sender);
        res.debt.mint(sender, maxTokenIn);
        res.debt.approve(address(res.order), maxTokenIn);
        res.order.swapTokenToExactToken(res.debt, res.ft, sender, ftOutAmt, maxTokenIn, block.timestamp + 1 hours);
        assertEq(res.ft.balanceOf(sender), ftOutAmt);
        (, uint128 debtAmt,) = res.gt.loanInfo(gtId);
        assertGt(debtAmt, 100e8);
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

    // New tests for addLiquidity / removeLiquidity
    function testAddLiquidityDepositsDebtToPool() public {
        vm.startPrank(maker);

        uint256 depositAmt = 50e8;
        // give maker some debt and approve order
        res.debt.mint(maker, depositAmt);
        res.debt.approve(address(res.order), depositAmt);

        // capture balances before
        uint256 ftBefore = res.ft.balanceOf(address(res.order));
        uint256 xtBefore = res.xt.balanceOf(address(res.order));
        uint256 orderDebtBefore = res.debt.balanceOf(address(res.order));
        uint256 poolSharesBefore = pool.balanceOf(address(res.order));
        uint256 makerBefore = res.debt.balanceOf(maker);

        // compute expected burn amount from FT/XT
        uint256 maxBurned = ftBefore < xtBefore ? ftBefore : xtBefore;

        // call addLiquidity as owner
        res.order.addLiquidity(IERC20(address(res.debt)), depositAmt);

        vm.stopPrank();

        // capture balances after
        uint256 ftAfter = res.ft.balanceOf(address(res.order));
        uint256 xtAfter = res.xt.balanceOf(address(res.order));
        uint256 orderDebtAfter = res.debt.balanceOf(address(res.order));
        uint256 poolSharesAfter = pool.balanceOf(address(res.order));
        uint256 makerAfter = res.debt.balanceOf(maker);

        // expected shares minted for (depositAmt + maxBurned)
        uint256 expectedShares = pool.previewDeposit(depositAmt + maxBurned);

        // Assertions
        assertEq(makerAfter, makerBefore - depositAmt, "maker debt should decrease by deposit amount");
        assertEq(ftAfter, ftBefore - maxBurned, "ft should decrease by burned amount");
        assertEq(xtAfter, xtBefore - maxBurned, "xt should decrease by burned amount");
        assertEq(
            orderDebtAfter,
            orderDebtBefore,
            "order debt token balance should return to previous state (deposited to pool)"
        );
        assertEq(poolSharesAfter, poolSharesBefore + expectedShares, "pool shares should increase by expected amount");
    }

    function testRemoveLiquidityWithdrawsDebtToRecipient() public {
        vm.startPrank(maker);

        uint256 withdrawAmt = 20e8;
        address recipient = sender;

        // ensure order has some pool assets (setUp deposited some)
        uint256 orderSharesBefore = pool.balanceOf(address(res.order));
        vm.assume(orderSharesBefore > 0);

        // capture balances before
        uint256 ftBefore = res.ft.balanceOf(address(res.order));
        uint256 xtBefore = res.xt.balanceOf(address(res.order));
        uint256 recipientBefore = res.debt.balanceOf(recipient);

        uint256 maxBurned = ftBefore < xtBefore ? ftBefore : xtBefore;

        // call removeLiquidity as owner
        res.order.removeLiquidity(IERC20(address(res.debt)), withdrawAmt, recipient);

        vm.stopPrank();

        // capture balances after
        uint256 ftAfter = res.ft.balanceOf(address(res.order));
        uint256 xtAfter = res.xt.balanceOf(address(res.order));
        uint256 recipientAfter = res.debt.balanceOf(recipient);
        uint256 orderSharesAfter = pool.balanceOf(address(res.order));

        // recipient should receive total `withdrawAmt`
        assertEq(recipientAfter - recipientBefore, withdrawAmt, "recipient should receive full withdraw amount");

        if (maxBurned >= withdrawAmt) {
            // all provided by burning ft/xt
            assertEq(ftAfter, ftBefore - withdrawAmt, "ft should decrease by withdraw amount when covered by ft/xt");
            assertEq(xtAfter, xtBefore - withdrawAmt, "xt should decrease by withdraw amount when covered by ft/xt");
            assertEq(orderSharesAfter, orderSharesBefore, "no pool shares should be withdrawn when ft/xt cover amount");
        } else {
            // partially from burning and partially from pool withdraw
            assertEq(ftAfter, ftBefore - maxBurned, "ft should decrease by maxBurned when partially covered");
            assertEq(xtAfter, xtBefore - maxBurned, "xt should decrease by maxBurned when partially covered");
            uint256 assetsFromPool = withdrawAmt - maxBurned;
            uint256 expectedSharesBurned = pool.previewWithdraw(assetsFromPool);
            assertEq(
                orderSharesBefore - orderSharesAfter,
                expectedSharesBurned,
                "pool shares burned should match previewWithdraw"
            );
        }
    }

    // Fuzz test: remove liquidity by specifying pool share amount
    function testFuzz_removeLiquidityAsShare(uint256 shares) public {
        vm.startPrank(maker);

        // order must have shares from setUp
        uint256 orderSharesBefore = pool.balanceOf(address(res.order));
        vm.assume(orderSharesBefore > 0);

        // bound shares to [1, orderSharesBefore]
        uint256 sharesToRemove = (shares % orderSharesBefore) + 1;

        // Ensure the order has some ft/xt reserves so _pool.deposit(maxBurned, recipient) path is executed.
        uint256 mintAmt = 10e8;
        // give maker debt and approve market to mint ft/xt to the order
        res.debt.mint(maker, mintAmt);
        res.debt.approve(address(res.market), mintAmt);
        // mint ft/xt to the order
        res.market.mint(address(res.order), mintAmt);

        // capture balances before
        uint256 makerBefore = pool.balanceOf(maker);
        uint256 ftBefore = res.ft.balanceOf(address(res.order));
        uint256 xtBefore = res.xt.balanceOf(address(res.order));

        uint256 maxBurned = ftBefore < xtBefore ? ftBefore : xtBefore;
        // ensure we exercise the branch that deposits the burned debt back to the pool for recipient
        vm.assume(maxBurned > 0);

        // expected shares minted by depositing `maxBurned` debt tokens to pool
        uint256 expectedDepositShares = pool.previewDeposit(maxBurned);

        // remove pool shares from order to maker
        res.order.removeLiquidity(IERC20(address(pool)), sharesToRemove, maker);

        vm.stopPrank();

        // assertions: pool shares moved from order to maker and deposited shares minted to maker
        assertEq(pool.balanceOf(address(res.order)), orderSharesBefore + expectedDepositShares - sharesToRemove);
        assertEq(pool.balanceOf(maker), makerBefore + sharesToRemove);
        // ft/xt reserves should decrease by `maxBurned` since that debt was deposited to pool for maker
        assertEq(res.ft.balanceOf(address(res.order)), ftBefore - maxBurned);
        assertEq(res.xt.balanceOf(address(res.order)), xtBefore - maxBurned);
    }
} // end OrderTestV2WithPool

// Mock contracts for testing
contract MockSwapCallback is ISwapCallback {
    int256 public deltaFt;
    int256 public deltaXt;

    function afterSwap(uint256, uint256, int256 deltaFt_, int256 deltaXt_) external override {
        deltaFt = deltaFt_;
        deltaXt = deltaXt_;
    }
}
