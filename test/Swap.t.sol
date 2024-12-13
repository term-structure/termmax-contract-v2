// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";

import {IFlashLoanReceiver} from "../contracts/core/IFlashLoanReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "../contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import "../contracts/core/storage/TermMaxStorage.sol";

contract SwapTest is Test {
    using JSONLoader for *;
    DeployUtils.Res res;

    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    function setUp() public {
        vm.startPrank(deployer);
        testdata = vm.readFile(
            string.concat(vm.projectRoot(), "/test/testdata/testdata.json")
        );

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig = JSONLoader.getMarketConfigFromJson(
            treasurer,
            testdata,
            ".marketConfig"
        );
        marketConfig.minApr = -0.9e8;
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );

        vm.warp(
            vm.parseUint(
                vm.parseJsonString(testdata, ".marketConfig.currentTime")
            )
        );

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_DAI_1.eth"
            )
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(
                testdata,
                ".priceData.ETH_2000_DAI_1.dai"
            )
        );

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(uint128(amount));

        vm.stopPrank();
    }

    function testBuyFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        uint actualOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut")
        );
        uint fee = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testBuyFt.output.fee")
        );
        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testBuyFt.contractState"
            );
        vm.expectEmit();
        emit ITermMaxMarket.BuyToken(
            sender,
            res.ft,
            underlyingAmtIn,
            minTokenOut,
            uint128(actualOut),
            uint128(fee),
            int64(expectedState.apr),
            uint128(expectedState.ftReserve),
            uint128(expectedState.xtReserve)
        );
        uint256 netOut = res.market.buyFt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        StateChecker.checkMarketState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.ft.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyAllFt() public {
        vm.startPrank(sender);

        uint underlyingAmtIn = 100000000000e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                TermMaxCurve.LiquidityIsZeroAfterTransaction.selector
            )
        );
        res.market.buyFt(uint128(underlyingAmtIn), 0, res.marketConfig.lsf);
        vm.stopPrank();
    }

    function testBuyFtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(
                vm.parseJsonString(
                    testdata,
                    ".expected.testBuyFt.output.netOut"
                )
            )
        );
        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = expectedNetOut + 1;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.UnexpectedAmount.selector,
                minTokenOut,
                expectedNetOut
            )
        );
        res.market.buyFt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testBuyFtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.buyFt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testBuyFtAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.buyFt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testBuyFtWhenAprTooSmall() public {
        int64 minApr = marketConfig.apr - 1;
        marketConfig.minApr = minApr;
        vm.prank(deployer);
        res.market.updateMarketConfig(marketConfig);

        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        vm.expectRevert(abi.encodeWithSelector(
            ITermMaxMarket.AprLessThanMinApr.selector,
            11784596,
            minApr
        ));
        res.market.buyFt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testBuyXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        uint actualOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut")
        );
        uint fee = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testBuyXt.output.fee")
        );
        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testBuyXt.contractState"
            );
        vm.expectEmit();
        emit ITermMaxMarket.BuyToken(
            sender,
            res.xt,
            underlyingAmtIn,
            minTokenOut,
            uint128(actualOut),
            uint128(fee),
            int64(expectedState.apr),
            uint128(expectedState.ftReserve),
            uint128(expectedState.xtReserve)
        );
        uint256 netOut = res.market.buyXt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        StateChecker.checkMarketState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.xt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyAllXt() public {
        vm.startPrank(sender);

        uint underlyingAmtIn = 100000000000e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                TermMaxCurve.LiquidityIsZeroAfterTransaction.selector
            )
        );
        res.market.buyXt(uint128(underlyingAmtIn), 0, res.marketConfig.lsf);
        vm.stopPrank();
    }

    function testBuyXtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(
                vm.parseJsonString(
                    testdata,
                    ".expected.testBuyXt.output.netOut"
                )
            )
        );
        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = expectedNetOut + 1;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.UnexpectedAmount.selector,
                minTokenOut,
                expectedNetOut
            )
        );
        res.market.buyXt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testBuyXtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.buyXt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testBuyXtAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.buyXt(underlyingAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = 0e8;
        res.ft.approve(address(res.market), ftAmtIn);

        uint actualOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut")
        );
        uint fee = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testSellFt.output.fee")
        );
        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testSellFt.contractState"
            );
        vm.expectEmit();
        emit ITermMaxMarket.SellToken(
            sender,
            res.ft,
            ftAmtIn,
            minTokenOut,
            uint128(actualOut),
            uint128(fee),
            int64(expectedState.apr),
            uint128(expectedState.ftReserve),
            uint128(expectedState.xtReserve)
        );
        uint256 netOut = res.market.sellFt(ftAmtIn, minTokenOut, res.marketConfig.lsf);

        StateChecker.checkMarketState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.ft.balanceOf(sender) == 0);
        assert(res.underlying.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testSellFtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(
                vm.parseJsonString(
                    testdata,
                    ".expected.testSellFt.output.netOut"
                )
            )
        );
        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = expectedNetOut + 1;

        res.ft.approve(address(res.market), ftAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.UnexpectedAmount.selector,
                minTokenOut,
                expectedNetOut
            )
        );
        res.market.sellFt(ftAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellFtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(res.market), ftAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.sellFt(ftAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellFtAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(res.market), ftAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.sellFt(ftAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = 0e8;
        res.xt.approve(address(res.market), xtAmtIn);

        uint actualOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut")
        );
        uint fee = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testSellXt.output.fee")
        );
        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testSellXt.contractState"
            );
        vm.expectEmit();
        emit ITermMaxMarket.SellToken(
            sender,
            res.xt,
            xtAmtIn,
            minTokenOut,
            uint128(actualOut),
            uint128(fee),
            int64(expectedState.apr),
            uint128(expectedState.ftReserve),
            uint128(expectedState.xtReserve)
        );
        uint256 netOut = res.market.sellXt(xtAmtIn, minTokenOut, res.marketConfig.lsf);

        StateChecker.checkMarketState(res, expectedState);

        assert(netOut == actualOut);
        assert(res.xt.balanceOf(sender) == 0);
        assert(res.underlying.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testSellXtMinTokenOut() public {
        vm.startPrank(sender);

        uint128 expectedNetOut = uint128(
            vm.parseUint(
                vm.parseJsonString(
                    testdata,
                    ".expected.testSellXt.output.netOut"
                )
            )
        );
        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = expectedNetOut + 1;

        res.xt.approve(address(res.market), xtAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.UnexpectedAmount.selector,
                minTokenOut,
                expectedNetOut
            )
        );
        res.market.sellXt(xtAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellXtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(res.market), xtAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.sellXt(xtAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellXtAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut, res.marketConfig.lsf)
        );
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(res.market), xtAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.sellXt(xtAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testSellXtWhenAprTooSmall() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut, res.marketConfig.lsf)
        );
        vm.stopPrank();
        int64 minApr = res.market.config().apr - 1;
        marketConfig.minApr = minApr;
        vm.prank(deployer);
        res.market.updateMarketConfig(marketConfig);

        vm.startPrank(sender);
        uint128 minTokenOut = 0e8;
        res.xt.approve(address(res.market), xtAmtIn);
        
        vm.expectRevert(abi.encodeWithSelector(
            ITermMaxMarket.AprLessThanMinApr.selector,
            12002705,
            minApr
        ));
        res.market.sellXt(xtAmtIn, minTokenOut, res.marketConfig.lsf);

        vm.stopPrank();
    }

    function testLever() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 1e18;
        uint128 debtAmt = 95e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(res.gt), collateralAmtIn);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        res.market.issueFt(
            debtAmt,
            abi.encode(collateralAmtIn)
        );
        state.collateralReserve += collateralAmtIn;
        StateChecker.checkMarketState(res, state);

        vm.stopPrank();
    }

    function testLeverBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 1e18;
        uint128 debtAmt = 95e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(res.gt), collateralAmtIn);

        vm.warp(res.market.config().maturity - 1);
        res.market.issueFt(debtAmt, abi.encode(collateralAmtIn));

        vm.stopPrank();
    }

    function testLeverAfterMaturity() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 1e18;
        uint128 debtAmt = 95e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(res.gt), collateralAmtIn);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.issueFt(debtAmt, abi.encode(collateralAmtIn));

        vm.stopPrank();
    }

    function testRedeemFtAndXtToUnderlying() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 1e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmt = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut, res.marketConfig.lsf) / 2
        );

        uint128 underlyingAmtInForBuyFt = 9e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);

        res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf);

        uint128 underlyingAmtToRedeem = xtAmt;
        uint128 xtAmtToRedeem = underlyingAmtToRedeem;
        uint128 ftAmtToRedeem = uint128((underlyingAmtToRedeem *
            res.market.config().initialLtv + Constants.DECIMAL_BASE - 1) / Constants.DECIMAL_BASE);
        res.xt.approve(address(res.market), xtAmtToRedeem);
        res.ft.approve(address(res.market), ftAmtToRedeem);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        emit ITermMaxMarket.RemoveLiquidity(sender, xtAmtToRedeem, uint128(state.ftReserve),
            uint128(state.xtReserve));
        res.market.redeemFtAndXtToUnderlying(xtAmtToRedeem);
        state.underlyingReserve -= underlyingAmtToRedeem;
        StateChecker.checkMarketState(res, state);

        vm.stopPrank();
    }

    function testRedeemFtAndXtToUnderlyingBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 1e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmt = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut, res.marketConfig.lsf) / 2
        );

        uint128 underlyingAmtInForBuyFt = 9e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        
        res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf);

        uint128 underlyingAmtToRedeem = xtAmt;
        uint128 xtAmtToRedeem = underlyingAmtToRedeem;
        uint128 ftAmtToRedeem = uint128((underlyingAmtToRedeem *
            res.market.config().initialLtv + Constants.DECIMAL_BASE - 1) / Constants.DECIMAL_BASE);
        res.xt.approve(address(res.market), xtAmtToRedeem);
        res.ft.approve(address(res.market), ftAmtToRedeem);

        vm.warp(res.market.config().maturity - 1);
        res.market.redeemFtAndXtToUnderlying(xtAmtToRedeem);

        vm.stopPrank();
    }

    function testRedeemFtAndXtToUnderlyingAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 1e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmt = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut, res.marketConfig.lsf) / 2
        );

        uint128 underlyingAmtInForBuyFt = 9e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        res.market.buyFt(underlyingAmtInForBuyFt, minFtOut, res.marketConfig.lsf);

        uint128 underlyingAmtToRedeem = xtAmt;
        uint128 xtAmtToRedeem = underlyingAmtToRedeem;
        uint128 ftAmtToRedeem = uint128((underlyingAmtToRedeem *
            res.market.config().initialLtv) / Constants.DECIMAL_BASE);
        res.xt.approve(address(res.market), xtAmtToRedeem);
        res.ft.approve(address(res.market), ftAmtToRedeem);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.redeemFtAndXtToUnderlying(xtAmtToRedeem);

        vm.stopPrank();
    }

    function testLeverageByXt() public {
        MockOuter outer = new MockOuter(res);

        vm.startPrank(sender);
        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut, res.marketConfig.lsf)
        );
        uint128 collateralAmtIn = 1e18;
        res.collateral.mint(sender, collateralAmtIn);
        res.xt.approve(address(outer), xtAmtIn);
        bytes memory callbackData = abi.encode(collateralAmtIn);
        outer.leverageByXt(sender, xtAmtIn, callbackData);
        vm.stopPrank();
    }

    function testBuyFtWithDifferentLsf() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        // Try to buy with different LSF than market config
        uint32 oldLsf = res.marketConfig.lsf;
        vm.stopPrank();
        vm.prank(deployer);
        res.marketConfig.lsf = oldLsf + 1;
        res.market.updateMarketConfig(res.marketConfig);

        vm.expectRevert(ITermMaxMarket.LsfChanged.selector);
        vm.prank(sender);
        res.market.buyFt(underlyingAmtIn, minTokenOut, oldLsf);
    }

    function testSellFtWithDifferentLsf() public {
        vm.startPrank(sender);

        // First buy FT with correct LSF
        uint128 underlyingAmtIn = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtIn, minFtOut, res.marketConfig.lsf)
        );

        // Try to sell with different LSF
        res.ft.approve(address(res.market), ftAmtIn);
        uint32 oldLsf = res.marketConfig.lsf;
        vm.stopPrank();
        vm.prank(deployer);
        res.marketConfig.lsf = oldLsf + 1;
        res.market.updateMarketConfig(res.marketConfig);

        vm.expectRevert(ITermMaxMarket.LsfChanged.selector);
        vm.prank(sender);
        res.market.sellFt(ftAmtIn, 0, oldLsf);
    }
}

contract MockOuter is IFlashLoanReceiver {
    DeployUtils.Res res;

    constructor(DeployUtils.Res memory _res) {
        res = _res;
    }

    function executeOperation(
        address,
        IERC20,
        uint256,
        bytes calldata data
    ) external returns (bytes memory collateralData) {
        uint128 collateralAmt = abi.decode(data, (uint128));
        res.collateral.mint(address(this), collateralAmt);
        return data;
    }

    function leverageByXt(
        address receiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) external returns (uint256 gtId) {
        uint128 collateralAmt = abi.decode(callbackData, (uint128));
        res.xt.transferFrom(msg.sender, address(this), xtAmt);
        res.xt.approve(address(res.market), xtAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        gtId = res.market.leverageByXt(receiver, xtAmt, callbackData);
    }
}
