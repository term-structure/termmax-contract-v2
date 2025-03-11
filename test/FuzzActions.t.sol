pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {TermMaxMarket, Constants, SafeCast} from "contracts/TermMaxMarket.sol";
import {TermMaxOrder, OrderConfig, ISwapCallback} from "contracts/TermMaxOrder.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockOrder} from "contracts/test/MockOrder.sol";
import {IMintableERC20, MintableERC20} from "contracts/tokens/MintableERC20.sol";
import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
import {IOracle, OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
import {IOrderManager, OrderManager} from "contracts/vault/OrderManager.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/storage/TermMaxStorage.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import "forge-std/Test.sol";

contract FuzzActionsTest is Test {
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
        res.order = res.market.createOrder(maker, res.orderConfig.maxXtReserve, afterSwap, res.orderConfig.curveCuts);

        uint256 ftReserve = vm.parseJsonUint(testdata, ".orderConfig.ftReserve");
        uint256 xtReserve = vm.parseJsonUint(testdata, ".orderConfig.xtReserve");
        res.debt.mint(admin, ftReserve + xtReserve);
        res.debt.approve(address(res.market), ftReserve + xtReserve);
        res.market.mint(admin, ftReserve + xtReserve);
        res.ft.transfer(address(res.order), ftReserve);
        res.xt.transfer(address(res.order), xtReserve);

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

        uint256 netAmt;
        if (isExact) {
            netAmt = res.order.swapTokenToExactToken(
                tokenIn, tokenOut, taker, uint128(action.firstAmt), type(uint128).max, block.timestamp + 1 hours
            );
        } else {
            netAmt = res.order.swapExactTokenToToken(
                tokenIn, tokenOut, taker, uint128(action.firstAmt), 0, block.timestamp + 1 hours
            );
        }
        assertEq(netAmt, action.secondAmt, "net amt not as expected");
        assertEq(res.ft.balanceOf(address(res.order)), action.ftReserve);
        assertEq(res.xt.balanceOf(address(res.order)), action.xtReserve);
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

    constructor(IERC20 ft_, IERC20 xt_) {
        ft = ft_;
        xt = xt_;
    }

    function afterSwap(uint256 ftReserve_, uint256 xtReserve_, int256 deltaFt_, int256 deltaXt_) external override {
        deltaFt = deltaFt_;
        deltaXt = deltaXt_;
        if (ftReserve == 0 || xtReserve == 0) {
            ftReserve = int256(ftReserve_);
            xtReserve = int256(xtReserve_);
            return;
        } else {
            ftReserve += deltaFt;
            xtReserve += deltaXt;
            require(uint256(ftReserve) == ftReserve_, "ft reserve not as expected");
            require(uint256(xtReserve) == xtReserve_, "xt reserve not as expected");
        }
    }
}
