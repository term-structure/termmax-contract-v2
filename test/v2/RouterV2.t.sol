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
    RouterEvents
} from "contracts/v2/router/TermMaxRouterV2.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {MockSwapAdapterV2} from "contracts/v2/test/MockSwapAdapterV2.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {TermMaxOrderV2, OrderInitialParams} from "contracts/v2/TermMaxOrderV2.sol";

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

        vm.stopPrank();

        vm.prank(maker);
        res.order.updateOrder(orderConfig, 0, 0);
    }

    function testSetAdapterWhitelist() public {
        vm.startPrank(deployer);

        address randomAdapter = vm.randomAddress();
        res.router.setAdapterWhitelist(randomAdapter, true);
        assertTrue(res.router.adapterWhitelist(randomAdapter));

        res.router.setAdapterWhitelist(randomAdapter, false);
        assertFalse(res.router.adapterWhitelist(randomAdapter));

        vm.stopPrank();
    }

    function testSetAdapterWhitelistUnauthorized() public {
        vm.startPrank(sender);

        address randomAdapter = vm.randomAddress();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(sender)));
        res.router.setAdapterWhitelist(randomAdapter, true);

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

    function testPlaceOrderForV1() public {
        vm.startPrank(sender);

        uint256 debtTokenToDeposit = 1e8;
        uint128 ftToDeposit = 2e8;
        uint128 xtToDeposit = 0;

        res.debt.mint(sender, debtTokenToDeposit);
        deal(address(res.ft), sender, ftToDeposit);
        res.debt.approve(address(res.router), debtTokenToDeposit);
        res.ft.approve(address(res.router), ftToDeposit);
        res.xt.approve(address(res.router), xtToDeposit);
        uint256 collateralToMintGt = 1e18;
        res.collateral.mint(sender, collateralToMintGt);
        res.collateral.approve(address(res.router), collateralToMintGt);

        (ITermMaxOrder order, uint256 gtId) = res.router.placeOrderForV1(
            res.market, sender, collateralToMintGt, debtTokenToDeposit, ftToDeposit, xtToDeposit, orderConfig
        );

        assertEq(gtId, 1);
        assertEq(order.maker(), sender);
        assertEq(res.ft.balanceOf(address(order)), ftToDeposit + debtTokenToDeposit);
        assertEq(res.xt.balanceOf(address(order)), xtToDeposit + debtTokenToDeposit);

        vm.stopPrank();
    }

    function testPlaceOrderForV2() public {
        vm.startPrank(sender);

        uint256 debtTokenToDeposit = 1e8;
        uint128 ftToDeposit = 2e8;
        uint128 xtToDeposit = 0;

        res.debt.mint(sender, debtTokenToDeposit);
        deal(address(res.ft), sender, ftToDeposit);
        res.debt.approve(address(res.router), debtTokenToDeposit);
        res.ft.approve(address(res.router), ftToDeposit);
        res.xt.approve(address(res.router), xtToDeposit);
        uint256 collateralToMintGt = 1e18;
        res.collateral.mint(sender, collateralToMintGt);
        res.collateral.approve(address(res.router), collateralToMintGt);

        OrderInitialParams memory initialParams;
        initialParams.maker = sender;
        initialParams.orderConfig = orderConfig;
        initialParams.virtualXtReserve = 1e8;
        (ITermMaxOrder order, uint256 gtId) = res.router.placeOrderForV2(
            res.market, collateralToMintGt, debtTokenToDeposit, ftToDeposit, xtToDeposit, initialParams
        );

        assertEq(gtId, order.orderConfig().gtId);
        assertEq(order.maker(), sender);
        assertEq(res.ft.balanceOf(address(order)), ftToDeposit + debtTokenToDeposit);
        assertEq(res.xt.balanceOf(address(order)), xtToDeposit + debtTokenToDeposit);

        vm.stopPrank();
    }
}
