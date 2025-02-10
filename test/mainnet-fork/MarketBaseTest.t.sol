// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {ITermMaxMarket, TermMaxMarket, MarketEvents} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IGearingToken, AbstractGearingToken} from "contracts/tokens/AbstractGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit, RouterErrors} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {EnvConfig} from "test/mainnet-fork/EnvConfig.sol";
import {TermMaxOrder, ITermMaxOrder} from "contracts/TermMaxOrder.sol";
import {ForkBaseTest} from "./ForkBaseTest.sol";
import {RouterEvents} from "contracts/events/RouterEvents.sol";
import {MockFlashLoanReceiver} from "contracts/test/MockFlashLoanReceiver.sol";
import "contracts/storage/TermMaxStorage.sol";

abstract contract MarketBaseTest is ForkBaseTest {
    address maker = vm.randomAddress();
    MarketInitialParams marketInitialParams;
    uint256 maxXtReserve = type(uint128).max;

    TermMaxMarket market;
    IMintableERC20 ft;
    IMintableERC20 xt;
    IGearingToken gt;
    IERC20 collateral;
    IERC20 debtToken;
    IOracle oracle;
    MockPriceFeed collateralPriceFeed;
    MockPriceFeed debtPriceFeed;
    ITermMaxOrder order;
    ITermMaxRouter router;

    function _initialize(bytes memory data) internal override {
        deal(maker, 1e18);
        CurveCuts memory curveCuts;
        (marketInitialParams, curveCuts) = abi.decode(data, (MarketInitialParams, CurveCuts));

        vm.startPrank(marketInitialParams.admin);

        oracle = deployOracleAggregator(marketInitialParams.admin);
        collateralPriceFeed = deployMockPriceFeed(marketInitialParams.admin);
        debtPriceFeed = deployMockPriceFeed(marketInitialParams.admin);
        oracle.setOracle(
            address(marketInitialParams.collateral), IOracle.Oracle(collateralPriceFeed, collateralPriceFeed, 365 days)
        );
        oracle.setOracle(address(marketInitialParams.debtToken), IOracle.Oracle(debtPriceFeed, debtPriceFeed, 365 days));
        string memory testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));
        // update oracle
        collateralPriceFeed.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        debtPriceFeed.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        market = TermMaxMarket(
            deployFactory(marketInitialParams.admin).createMarket(
                keccak256("GearingTokenWithERC20"), marketInitialParams, 0
            )
        );

        (ft, xt, gt,,) = market.tokens();
        debtToken = marketInitialParams.debtToken;
        collateral = IERC20(marketInitialParams.collateral);

        order = market.createOrder(maker, maxXtReserve, ISwapCallback(address(0)), curveCuts);

        router = deployRouter(marketInitialParams.admin);
        router.setMarketWhitelist(address(market), true);

        uint256 amount = 150e8;
        deal(address(debtToken), maker, amount);

        debtToken.approve(address(market), amount);
        market.mint(address(order), amount);

        vm.stopPrank();
    }

    function testMint() public {
        address to = vm.randomAddress();
        uint256 amount = 100e8;
        deal(address(debtToken), to, amount);
        deal(to, 1e18);
        vm.startPrank(to);
        debtToken.approve(address(market), amount);
        market.mint(to, amount);
        vm.assertEq(ft.balanceOf(to), amount);
        vm.assertEq(xt.balanceOf(to), amount);
        vm.stopPrank();
    }

    function testBurn() public {
        address taker = vm.randomAddress();
        uint256 amount = 100e8;
        deal(taker, 1e18);
        deal(address(debtToken), taker, amount);
        vm.startPrank(taker);
        debtToken.approve(address(market), amount);
        market.mint(taker, amount);

        ft.approve(address(market), amount);
        xt.approve(address(market), amount);
        market.burn(taker, amount);
        vm.assertEq(debtToken.balanceOf(taker), amount);
        vm.stopPrank();
    }

    function testRedeem() public {
        MarketConfig memory marketConfig = market.config();
        marketConfig.feeConfig.redeemFeeRatio = 0.01e8;
        vm.prank(marketInitialParams.admin);
        market.updateMarketConfig(marketConfig);

        address bob = vm.randomAddress();
        address alice = vm.randomAddress();
        deal(bob, 1e18);
        deal(alice, 1e18);

        uint128 depositAmt = 1000e8;
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(bob);
        deal(address(debtToken), bob, depositAmt);
        debtToken.approve(address(market), depositAmt);
        market.mint(bob, depositAmt);

        xt.transfer(alice, debtAmt);
        vm.stopPrank();

        vm.startPrank(alice);

        MockFlashLoanReceiver receiver = new MockFlashLoanReceiver(market);
        deal(address(collateral), address(receiver), collateralAmt);

        xt.approve(address(receiver), debtAmt);
        receiver.leverageByXt(debtAmt, abi.encode(alice, collateralAmt));
        vm.stopPrank();

        vm.warp(marketConfig.maturity + Constants.LIQUIDATION_WINDOW);

        vm.startPrank(bob);
        ft.approve(address(market), depositAmt);

        uint256 redeemFee = (marketConfig.feeConfig.redeemFeeRatio * (depositAmt - debtAmt)) / Constants.DECIMAL_BASE;
        vm.expectEmit();
        emit MarketEvents.Redeem(
            bob,
            bob,
            uint128(Constants.DECIMAL_BASE_SQ),
            uint128(depositAmt - debtAmt - redeemFee),
            uint128(redeemFee),
            abi.encode(collateralAmt)
        );
        market.redeem(depositAmt, bob);

        assertEq(debtToken.balanceOf(bob), depositAmt - debtAmt - redeemFee);
        assertEq(collateral.balanceOf(bob), collateralAmt);
        assertEq(debtToken.balanceOf(address(market)), 0);
        assertEq(ft.balanceOf(bob), 0);
        vm.stopPrank();
    }

    function testBorrow() public {
        address taker = vm.randomAddress();
        uint256 collInAmt = 1e18;
        uint128 borrowAmt = 80e8;
        uint128 maxDebtAmt = 100e8;

        vm.startPrank(taker);

        ITermMaxOrder[] memory orders = new ITermMaxOrder[](1);
        orders[0] = order;
        uint128[] memory tokenAmtsWantBuy = new uint128[](1);
        tokenAmtsWantBuy[0] = borrowAmt;

        deal(address(collateral), taker, collInAmt);
        collateral.approve(address(router), collInAmt);

        vm.expectEmit();
        uint256 expectedGtId = 1;
        emit RouterEvents.Borrow(market, expectedGtId, taker, taker, collInAmt, maxDebtAmt, borrowAmt);
        uint256 gtId = router.borrowTokenFromCollateral(taker, market, collInAmt, orders, tokenAmtsWantBuy, maxDebtAmt);
        (address owner, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(gtId);
        assertEq(owner, taker);
        assertEq(collInAmt, abi.decode(collateralData, (uint256)));
        assert(debtAmt <= maxDebtAmt);
        assertEq(debtToken.balanceOf(taker), borrowAmt);

        vm.stopPrank();
    }
}
