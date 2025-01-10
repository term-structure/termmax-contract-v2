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
import {MockSwapAdapter} from "contracts/test/MockSwapAdapter.sol";
import "contracts/storage/TermMaxStorage.sol";

contract RouterTest is Test {
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

        res.router = DeployUtils.deployRouter(deployer);
        res.router.setMarketWhitelist(address(res.market), true);
        MockSwapAdapter adapter = new MockSwapAdapter(pool);

        res.router.setAdapterWhitelist(address(adapter), true);

        vm.stopPrank();
    }

    function testSetMarketWhitelist() public {
        vm.startPrank(deployer);

        address market = vm.randomAddress();
        res.router.setMarketWhitelist(market, true);
        assertTrue(res.router.marketWhitelist(market));

        res.router.setMarketWhitelist(market, false);
        assertFalse(res.router.marketWhitelist(market));

        vm.stopPrank();
    }

    function testSetMarketWhitelistUnauthorized() public {
        vm.startPrank(sender);

        address market = vm.randomAddress();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(sender)));
        res.router.setMarketWhitelist(market, true);

        vm.stopPrank();
    }

    function testSetAdapterWhitelist() public {
        vm.startPrank(deployer);

        address adapter = vm.randomAddress();
        res.router.setAdapterWhitelist(adapter, true);
        assertTrue(res.router.adapterWhitelist(adapter));

        res.router.setAdapterWhitelist(adapter, false);
        assertFalse(res.router.adapterWhitelist(adapter));

        vm.stopPrank();
    }

    function testSetAdapterWhitelistUnauthorized() public {
        vm.startPrank(sender);

        address adapter = vm.randomAddress();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(sender)));
        res.router.setAdapterWhitelist(adapter, true);

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

    function testSwapExactTokenToToken() public {
        //TODO check output
        vm.startPrank(sender);

        uint128 amountIn = 100e8;
        uint128[] memory tradingAmts = new uint128[](2);
        tradingAmts[0] = 50e8;
        tradingAmts[1] = 50e8;
        uint128 mintTokenOut = 80e8;

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](2);
        orders[0] = res.order;
        orders[1] = res.order;

        res.debt.mint(sender, amountIn);
        res.debt.approve(address(res.router), amountIn);
        uint256 netOut = res.router.swapExactTokenToToken(res.debt, res.ft, sender, orders, tradingAmts, mintTokenOut);
        assertEq(netOut, res.ft.balanceOf(sender));

        assertEq(res.debt.balanceOf(sender), 0);

        vm.stopPrank();
    }

    function testSwapTokenToExactToken() public {
        //TODO check output
        vm.startPrank(sender);

        uint128 amountOut = 90e8;
        uint128[] memory tradingAmts = new uint128[](2);
        tradingAmts[0] = 45e8;
        tradingAmts[1] = 45e8;
        uint128 maxAmountIn = 100e8;

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](2);
        orders[0] = res.order;
        orders[1] = res.order;

        res.debt.mint(sender, maxAmountIn);
        res.debt.approve(address(res.router), maxAmountIn);

        uint256 balanceBefore = res.ft.balanceOf(sender);
        uint256 amountIn = res.router.swapTokenToExactToken(
            res.debt,
            res.ft,
            sender,
            orders,
            tradingAmts,
            maxAmountIn
        );
        uint256 balanceAfter = res.ft.balanceOf(sender);

        assertEq(maxAmountIn - amountIn, res.debt.balanceOf(sender));
        assertEq(res.ft.balanceOf(sender) - balanceBefore, amountOut);

        vm.stopPrank();
    }

    // function testSwapTokenToExactToken() public {
    //     vm.startPrank(sender);

    //     uint128 amountOut = 90e8;
    //     uint128 maxAmountIn = 100e8;

    //     res.debt.mint(sender, maxAmountIn);
    //     res.debt.approve(address(res.router), maxAmountIn);

    //     uint256 balanceBefore = res.ft.balanceOf(sender);
    //     uint256 amountIn = res.router.swapTokenToExactToken(
    //         res.market,
    //         res.debt,
    //         res.ft,
    //         sender,
    //         amountOut,
    //         maxAmountIn
    //     );
    //     uint256 balanceAfter = res.ft.balanceOf(sender);

    //     assertEq(balanceAfter - balanceBefore, amountOut);
    //     assertLe(amountIn, maxAmountIn);

    //     vm.stopPrank();
    // }

    // function testCreateOrder() public {
    //     vm.startPrank(sender);

    //     uint128 maxXtReserve = 1000e8;
    //     CurveCuts memory curveCuts = CurveCuts({a: 0, b: 0, c: 0, d: 0});

    //     ITermMaxOrder order = res.router.createOrder(
    //         res.market,
    //         sender,
    //         maxXtReserve,
    //         ISwapCallback(address(0)),
    //         curveCuts
    //     );

    //     assertEq(order.maker(), sender);
    //     assertEq(order.maxXtReserve(), maxXtReserve);

    //     vm.stopPrank();
    // }

    //     function testBorrow() public {
    //         vm.startPrank(sender);

    //         uint128 debtAmount = 100e8;
    //         uint256 collateralAmount = 1e18;

    //         res.collateral.mint(sender, collateralAmount);
    //         res.collateral.approve(address(res.router), collateralAmount);

    //         ITermMaxOrder order = res.router.createOrder(
    //             res.market,
    //             sender,
    //             1000e8,
    //             ISwapCallback(address(0)),
    //             CurveCuts({a: 0, b: 0, c: 0, d: 0})
    //         );

    //         uint256 gtId = res.router.borrow(res.market, order, res.ft, res.gt, debtAmount, collateralAmount, 0, sender);

    //         assertTrue(gtId > 0);
    //         assertEq(res.gt.ownerOf(gtId), sender);

    //         vm.stopPrank();
    //     }
}
