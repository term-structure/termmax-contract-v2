pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {TermMaxMarket, Constants, SafeCast} from "contracts/v1/TermMaxMarket.sol";
import {TermMaxOrder, OrderConfig, ISwapCallback} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockOrder} from "contracts/v1/test/MockOrder.sol";
import {IMintableERC20, MintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {SwapAdapter} from "contracts/v1/test/testnet/SwapAdapter.sol";
import {IOracle, OracleAggregator} from "contracts/v1/oracle/OracleAggregator.sol";
import {IOrderManager, OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/v1/storage/TermMaxStorage.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import "forge-std/Test.sol";

contract FuzzSwapTest is Test {
    using JSONLoader for *;
    using SafeCast for *;
    using DeployUtils for *;

    uint256 entities;

    address admin = vm.randomAddress();
    address maker = vm.randomAddress();
    address taker = vm.randomAddress();
    address treasurer = vm.randomAddress();

    string[] indexs = ["0", "1", "2", "3", "4", "5"];

    function setUp() public {
        string memory entitiesData = string.concat(vm.projectRoot(), "/test/testdata/fuzzSwap/entities.json");
        entities = vm.parseJsonUint(vm.readFile(entitiesData), ".entities");
    }

    function _initResources(string memory index) internal returns (DeployUtils.Res memory res) {
        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;
        string memory entityPath = string.concat(vm.projectRoot(), "/test/testdata/fuzzSwap/", index, ".json");
        string memory testdata = vm.readFile(entityPath);
        uint256 currentTime = vm.parseJsonUint(testdata, ".currentTime");
        vm.warp(currentTime);

        MarketConfig memory marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");

        vm.startPrank(admin);

        res = DeployUtils.deployMarket(admin, marketConfig, maxLtv, liquidationLtv);

        res.orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");

        MockSwapCallback afterSwap = new MockSwapCallback(res.ft, res.xt);

        res.order = res.market.createOrder(maker, res.orderConfig.maxXtReserve, afterSwap, res.orderConfig.curveCuts);

        uint256 orderInitialAmount = vm.parseJsonUint(testdata, ".orderInitialAmount");
        res.debt.mint(admin, orderInitialAmount);
        res.debt.approve(address(res.market), orderInitialAmount);
        res.market.mint(address(res.order), orderInitialAmount);

        res.swapRange = JSONLoader.getSwapRangeFromJson(testdata, ".maxInput");

        vm.stopPrank();
    }

    function testBuyFt(uint256 index, uint128 tokenAmtIn) public {
        console.log("buy ft", index, tokenAmtIn);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(tokenAmtIn > 0 && tokenAmtIn <= res.swapRange.buyFtMax);
        _buyFt(res, tokenAmtIn, 0);
    }

    function testBuyXt(uint256 index, uint128 tokenAmtIn) public {
        console.log("buy xt", index, tokenAmtIn);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(tokenAmtIn > 0 && tokenAmtIn <= res.swapRange.buyXtMax);
        _buyXt(res, tokenAmtIn, 0);
    }

    function testSellFt(uint256 index, uint128 ftAmtIn) public {
        console.log("sell ft", index, ftAmtIn);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(ftAmtIn > 0 && ftAmtIn <= res.swapRange.sellFtMax);
        _sellFt(res, ftAmtIn, 0);
    }

    function testSellXt(uint256 index, uint128 xtAmtIn) public {
        console.log("sell xt", index, xtAmtIn);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(xtAmtIn > 0 && xtAmtIn <= res.swapRange.sellXtMax);
        _sellXt(res, xtAmtIn, 0);
    }

    function testBuyExactFt(uint256 index, uint128 ftAmtOut) public {
        console.log("buy exact ft", index, ftAmtOut);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(ftAmtOut > 0 && ftAmtOut <= res.swapRange.buyExactFtMax);
        _buyExactFt(res, ftAmtOut, ftAmtOut);
    }

    function testBuyExactXt(uint256 index, uint128 xtAmtOut) public {
        console.log("buy exact xt", index, xtAmtOut);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(xtAmtOut > 0 && xtAmtOut <= res.swapRange.buyExactXtMax);
        _buyExactXt(res, xtAmtOut, xtAmtOut);
    }

    function testSellFtForExactToken(uint256 index, uint128 tokenAmtOut) public {
        console.log("sell ft for exact token", index, tokenAmtOut);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(tokenAmtOut > 0 && tokenAmtOut <= res.swapRange.sellFtForExactTokenMax);
        _sellFtForExactToken(res, tokenAmtOut, tokenAmtOut * 10);
    }

    function testSellXtForExactToken(uint256 index, uint128 tokenAmtOut) public {
        console.log("sell xt for exact token", index, tokenAmtOut);
        vm.assume(index < entities);
        DeployUtils.Res memory res = _initResources(indexs[index]);
        vm.assume(tokenAmtOut > 0 && tokenAmtOut <= res.swapRange.sellXtForExactTokenMax);
        _sellXtForExactToken(res, tokenAmtOut, tokenAmtOut * 10000);
    }

    function _buyFt(DeployUtils.Res memory res, uint128 tokenAmtIn, uint128 minFtAmtOut) internal {
        vm.startPrank(taker);

        res.debt.mint(taker, tokenAmtIn);
        res.debt.approve(address(res.order), tokenAmtIn);

        res.order.swapExactTokenToToken(res.debt, res.ft, taker, tokenAmtIn, minFtAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _buyXt(DeployUtils.Res memory res, uint128 tokenAmtIn, uint128 minXtAmtOut) internal {
        vm.startPrank(taker);

        res.debt.mint(taker, tokenAmtIn);
        res.debt.approve(address(res.order), tokenAmtIn);

        res.order.swapExactTokenToToken(res.debt, res.xt, taker, tokenAmtIn, minXtAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _sellFt(DeployUtils.Res memory res, uint128 ftAmtIn, uint128 minTokenAmtOut) internal {
        vm.startPrank(taker);
        res.debt.mint(taker, ftAmtIn);
        res.debt.approve(address(res.market), ftAmtIn);
        res.market.mint(taker, ftAmtIn);

        res.ft.approve(address(res.order), ftAmtIn);
        res.order.swapExactTokenToToken(res.ft, res.debt, taker, ftAmtIn, minTokenAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _sellXt(DeployUtils.Res memory res, uint128 xtAmtIn, uint128 minTokenAmtOut) internal {
        vm.startPrank(taker);
        res.debt.mint(taker, xtAmtIn);
        res.debt.approve(address(res.market), xtAmtIn);
        res.market.mint(taker, xtAmtIn);

        res.xt.approve(address(res.order), xtAmtIn);
        res.order.swapExactTokenToToken(res.xt, res.debt, taker, xtAmtIn, minTokenAmtOut, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _buyExactFt(DeployUtils.Res memory res, uint128 ftAmtOut, uint128 maxTokenAmtIn) internal {
        vm.startPrank(taker);
        res.debt.mint(taker, maxTokenAmtIn);
        res.debt.approve(address(res.order), maxTokenAmtIn);
        res.order.swapTokenToExactToken(res.debt, res.ft, taker, ftAmtOut, maxTokenAmtIn, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _buyExactXt(DeployUtils.Res memory res, uint128 xtAmtOut, uint128 maxTokenAmtIn) internal {
        vm.startPrank(taker);
        res.debt.mint(taker, maxTokenAmtIn);
        res.debt.approve(address(res.order), maxTokenAmtIn);
        res.order.swapTokenToExactToken(res.debt, res.xt, taker, xtAmtOut, maxTokenAmtIn, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _sellFtForExactToken(DeployUtils.Res memory res, uint128 tokenAmtOut, uint128 maxFtAmtIn) internal {
        vm.startPrank(taker);
        res.debt.mint(taker, maxFtAmtIn);
        res.debt.approve(address(res.market), maxFtAmtIn);
        res.market.mint(taker, maxFtAmtIn);

        res.ft.approve(address(res.order), maxFtAmtIn);
        res.order.swapTokenToExactToken(res.ft, res.debt, taker, tokenAmtOut, maxFtAmtIn, block.timestamp + 1 hours);
        vm.stopPrank();
    }

    function _sellXtForExactToken(DeployUtils.Res memory res, uint128 tokenAmtOut, uint128 maxXtAmtIn) internal {
        vm.startPrank(taker);
        res.debt.mint(taker, maxXtAmtIn);
        res.debt.approve(address(res.market), maxXtAmtIn);
        res.market.mint(taker, maxXtAmtIn);

        res.xt.approve(address(res.order), maxXtAmtIn);
        res.order.swapTokenToExactToken(res.xt, res.debt, taker, tokenAmtOut, maxXtAmtIn, block.timestamp + 1 hours);
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
