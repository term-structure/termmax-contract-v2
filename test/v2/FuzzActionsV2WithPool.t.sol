pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {MockERC4626} from "contracts/v2/test/MockERC4626.sol";
import "forge-std/Test.sol";

contract FuzzActionsTestV2WithPool is Test {
    using JSONLoader for *;
    using SafeCast for *;
    using DeployUtils for *;

    enum OpType {
        BUY_FT,
        BUY_XT,
        SELL_FT,
        SELL_XT,
        BUY_EXACT_FT,
        BUY_EXACT_XT,
        SELL_FT_FOR_EXACT_TOKEN,
        SELL_XT_FOR_EXACT_TOKEN
    }

    struct Action {
        uint256 opType;
        uint256 firstAmt;
        uint256 ftReserve;
        uint256 xtReserve;
        uint256 secondAmt;
        uint256 fee;
    }

    address admin = vm.randomAddress();
    address maker = vm.randomAddress();
    address taker = vm.randomAddress();
    address treasurer = vm.randomAddress();
    MockERC4626 pool;

    string path = string.concat(vm.projectRoot(), "/test/testdata/fuzzSwap/v2.json");

    function setUp() public {}

    function _initResources() internal returns (DeployUtils.Res memory res) {
        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;
        string memory entityPath = path;
        string memory testdata = vm.readFile(entityPath);
        uint256 currentTime = vm.parseJsonUint(testdata, ".currentTime");
        vm.warp(currentTime);

        MarketConfig memory marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");

        vm.startPrank(admin);

        res = DeployUtils.deployMarket(admin, marketConfig, maxLtv, liquidationLtv);

        res.orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        MockSwapCallback afterSwap = new MockSwapCallback(res.ft, res.xt);

        uint256 ftReserve = vm.parseJsonUint(testdata, ".orderConfig.ftReserve");
        uint256 xtReserve = vm.parseJsonUint(testdata, ".orderConfig.xtReserve");

        pool = new MockERC4626(res.debt);

        OrderInitialParams memory orderParams;
        orderParams.maker = maker;
        orderParams.orderConfig = res.orderConfig;
        orderParams.virtualXtReserve = xtReserve;
        orderParams.orderConfig.swapTrigger = ISwapCallback(address(afterSwap));
        orderParams.pool = pool;
        res.order = TermMaxOrderV2(address(res.market.createOrder(orderParams)));

        res.debt.mint(admin, ftReserve + xtReserve);
        res.debt.approve(address(pool), ftReserve + xtReserve);
        uint256 maxShares = ftReserve > xtReserve ? xtReserve : ftReserve;
        pool.deposit(maxShares, address(res.order));
        res.debt.approve(address(res.market), ftReserve + xtReserve - maxShares);
        res.market.mint(admin, ftReserve + xtReserve - maxShares);
        res.ft.transfer(address(res.order), ftReserve - maxShares);
        res.xt.transfer(address(res.order), xtReserve - maxShares);

        vm.label(address(res.order), "OrderV2");
        vm.label(address(res.market), "MarketV2");
        vm.label(address(res.debt), "DebtToken");
        vm.label(address(res.ft), "FTToken");
        vm.label(address(res.xt), "XTToken");
        vm.label(address(pool), "Pool");
        vm.label(maker, "Maker");
        vm.label(taker, "Taker");
        vm.label(treasurer, "Treasurer");
        vm.label(admin, "Admin");

        vm.stopPrank();
    }

    function _parseActions() internal returns (Action[] memory actions) {
        string memory json = vm.readFile(path);
        uint256 length = vm.parseJsonUint(json, ".actions.length");
        actions = new Action[](length);
        for (uint256 i = 0; i < length; i++) {
            string memory key = string.concat(".actions.", vm.toString(i));
            actions[i].opType = vm.parseJsonUint(json, string.concat(key, ".opType"));
            actions[i].firstAmt = vm.parseJsonUint(json, string.concat(key, ".firstAmt"));
            actions[i].secondAmt = vm.parseJsonUint(json, string.concat(key, ".secondAmt"));
            actions[i].ftReserve = vm.parseJsonUint(json, string.concat(key, ".contractState.ftReserve"));
            actions[i].xtReserve = vm.parseJsonUint(json, string.concat(key, ".contractState.xtReserve"));
            actions[i].fee = vm.parseJsonUint(json, string.concat(key, ".fee"));
        }
    }

    function testActions() public {
        DeployUtils.Res memory res = _initResources();
        Action[] memory actions = _parseActions();
        vm.startPrank(taker);
        uint256 max128 = type(uint128).max;
        res.debt.mint(taker, max128);
        res.debt.approve(address(res.market), max128);
        res.market.mint(taker, max128 / 2);
        res.debt.approve(address(res.order), max128);
        res.ft.approve(address(res.order), max128);
        res.xt.approve(address(res.order), max128);
        vm.stopPrank();

        for (uint256 i = 0; i < actions.length; i++) {
            _swapToken(res, actions[i]);
        }
    }

    function _swapToken(DeployUtils.Res memory res, Action memory action) internal {
        IERC20 tokenIn;
        IERC20 tokenOut;
        bool isExact;
        if (action.opType == uint256(OpType.BUY_FT)) {
            tokenIn = res.debt;
            tokenOut = res.ft;
            isExact = false;
            console.log("buy ft");
        } else if (action.opType == uint256(OpType.BUY_XT)) {
            tokenIn = res.debt;
            tokenOut = res.xt;
            isExact = false;
            console.log("buy xt");
        } else if (action.opType == uint256(OpType.SELL_FT)) {
            tokenIn = res.ft;
            tokenOut = res.debt;
            isExact = false;
            console.log("sell ft");
        } else if (action.opType == uint256(OpType.SELL_XT)) {
            tokenIn = res.xt;
            tokenOut = res.debt;
            isExact = false;
            console.log("sell xt");
        } else if (action.opType == uint256(OpType.BUY_EXACT_FT)) {
            tokenIn = res.debt;
            tokenOut = res.ft;
            isExact = true;
            console.log("buy exact ft");
        } else if (action.opType == uint256(OpType.BUY_EXACT_XT)) {
            tokenIn = res.debt;
            tokenOut = res.xt;
            isExact = true;
            console.log("buy exact xt");
        } else if (action.opType == uint256(OpType.SELL_FT_FOR_EXACT_TOKEN)) {
            tokenIn = res.ft;
            tokenOut = res.debt;
            isExact = true;
            console.log("sell ft for exact token");
        } else if (action.opType == uint256(OpType.SELL_XT_FOR_EXACT_TOKEN)) {
            tokenIn = res.xt;
            tokenOut = res.debt;
            isExact = true;
            console.log("sell xt for exact token");
        }

        vm.startPrank(taker);

        uint256 tokenInBalanceBefore = tokenIn.balanceOf(taker);
        uint256 tokenOutBalanceBefore = tokenOut.balanceOf(taker);

        uint256 netAmt;
        if (isExact) {
            netAmt = res.order.swapTokenToExactToken(
                tokenIn, tokenOut, taker, uint128(action.firstAmt), type(uint128).max, block.timestamp + 1 hours
            );
            uint256 tokenInBalanceAfter = tokenIn.balanceOf(taker);
            uint256 tokenOutBalanceAfter = tokenOut.balanceOf(taker);
            assertEq(tokenInBalanceBefore - tokenInBalanceAfter, action.secondAmt, "token in balance not as expected");
            assertEq(tokenOutBalanceAfter - tokenOutBalanceBefore, action.firstAmt, "token out balance not as expected");
        } else {
            netAmt = res.order.swapExactTokenToToken(
                tokenIn, tokenOut, taker, uint128(action.firstAmt), 0, block.timestamp + 1 hours
            );
            uint256 tokenInBalanceAfter = tokenIn.balanceOf(taker);
            uint256 tokenOutBalanceAfter = tokenOut.balanceOf(taker);
            assertEq(tokenInBalanceBefore - tokenInBalanceAfter, action.firstAmt, "token in balance not as expected");
            assertEq(
                tokenOutBalanceAfter - tokenOutBalanceBefore, action.secondAmt, "token out balance not as expected"
            );
        }
        assertEq(netAmt, action.secondAmt, "net amt not as expected");
        (uint256 ftReserve, uint256 xtReserve) = res.order.getRealReserves();
        console.log("ft reserve: %s, xt reserve: %s", ftReserve, xtReserve);
        uint256 shares = pool.balanceOf(address(res.order));
        console.log("shares in pool: %s", shares);
        console.log("assetsInPool", pool.convertToAssets(shares));
        console.log("ft balance in order: %s", res.ft.balanceOf(address(res.order)));
        console.log("xt balance in order: %s", res.xt.balanceOf(address(res.order)));
        assertEq(ftReserve, action.ftReserve, "ft reserve not as expected");
        assertEq(xtReserve, action.xtReserve, "xt reserve not as expected");
        vm.stopPrank();
    }
}

// Mock contracts for testing
contract MockSwapCallback is ISwapCallback {
    using SafeCast for *;

    int256 public deltaFt;
    int256 public deltaXt;
    int256 ftReserve;
    int256 xtReserve;
    IERC20 public ft;
    IERC20 public xt;

    error InvalidReserve(int256 ftReserve_, int256 xtReserve_, int256 expectedFtReserve, int256 expectedXtReserve);

    constructor(IERC20 ft_, IERC20 xt_) {
        ft = ft_;
        xt = xt_;
    }

    function afterSwap(uint256 ftReserve_, uint256 xtReserve_, int256 deltaFt_, int256 deltaXt_) external override {
        deltaFt = deltaFt_;
        deltaXt = deltaXt_;
        (uint256 realFtReserve, uint256 realXtReserve) = TermMaxOrderV2(msg.sender).getRealReserves();
        if (ftReserve == 0 && xtReserve == 0) {
            ftReserve = int256(realFtReserve) + deltaFt;
            xtReserve = int256(realXtReserve) + deltaXt;
            return;
        } else {
            ftReserve += deltaFt;
            xtReserve += deltaXt;
            require(
                ftReserve == int256(realFtReserve) + deltaFt,
                InvalidReserve(ftReserve, xtReserve, int256(realFtReserve) + deltaFt, int256(realXtReserve) + deltaXt)
            );
            require(
                xtReserve == int256(realXtReserve) + deltaXt,
                InvalidReserve(ftReserve, xtReserve, int256(realFtReserve) + deltaFt, int256(realXtReserve) + deltaXt)
            );
        }
    }
}
