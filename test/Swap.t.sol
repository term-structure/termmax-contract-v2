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
import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
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
        res.market.provideLiquidity(amount);

        vm.stopPrank();
    }

    function testBuyFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        uint256 netOut = res.market.buyFt(underlyingAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testBuyFt.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            netOut ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.testBuyFt.output.netOut"
                    )
                )
        );
        assert(res.ft.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyAllFt() public {
        vm.startPrank(sender);

        uint underlyingAmtIn = (10000e8 * uint256(marketConfig.initialLtv)) /
            Constants.DECIMAL_BASE;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.LiquidityIsZeroAfterTransaction.selector
            )
        );
        res.market.buyFt(uint128(underlyingAmtIn), 0);
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
        res.market.buyFt(underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testBuyFtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.buyFt(underlyingAmtIn, minTokenOut);

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
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        res.market.buyFt(underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testBuyXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        uint256 netOut = res.market.buyXt(underlyingAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testBuyXt.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            netOut ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.testBuyXt.output.netOut"
                    )
                )
        );
        assert(res.xt.balanceOf(sender) == netOut);

        vm.stopPrank();
    }

    function testBuyAllXt() public {
        vm.startPrank(sender);

        uint underlyingAmtIn = (10000e8 *
            Constants.DECIMAL_BASE -
            marketConfig.initialLtv) / Constants.DECIMAL_BASE;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.LiquidityIsZeroAfterTransaction.selector
            )
        );
        res.market.buyXt(uint128(underlyingAmtIn), 0);
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
        res.market.buyXt(underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testBuyXtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;

        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.buyXt(underlyingAmtIn, minTokenOut);

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
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        res.market.buyXt(underlyingAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut)
        );
        uint128 minTokenOut = 0e8;
        res.ft.approve(address(res.market), ftAmtIn);
        uint256 netOut = res.market.sellFt(ftAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testSellFt.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            netOut ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.testSellFt.output.netOut"
                    )
                )
        );
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
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut)
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
        res.market.sellFt(ftAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellFtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut)
        );
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(res.market), ftAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.sellFt(ftAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellFtAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut)
        );
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(res.market), ftAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        res.market.sellFt(ftAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut)
        );
        uint128 minTokenOut = 0e8;
        res.xt.approve(address(res.market), xtAmtIn);
        uint256 netOut = res.market.sellXt(xtAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.testSellXt.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            netOut ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.testSellXt.output.netOut"
                    )
                )
        );
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
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut)
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
        res.market.sellXt(xtAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellXtBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut)
        );
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(res.market), xtAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.sellXt(xtAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testSellXtAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXtOut)
        );
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(res.market), xtAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        res.market.sellXt(xtAmtIn, minTokenOut);

        vm.stopPrank();
    }

    function testLever() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 1e18;
        uint128 debtAmt = 95e8;
        uint128 minTokenOut = 0e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(res.gt), collateralAmtIn);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        (uint256 gtId, uint128 netOut) = res.market.issueFt(
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
        uint128 minTokenOut = 0e8;
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
        uint128 minTokenOut = 0e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(res.gt), collateralAmtIn);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
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
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut) / 2
        );

        uint128 underlyingAmtInForBuyFt = 9e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmt = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut) / 2
        );

        uint128 underlyingAmtToRedeem = xtAmt;
        uint128 xtAmtToRedeem = underlyingAmtToRedeem;
        uint128 ftAmtToRedeem = (underlyingAmtToRedeem *
            res.market.config().initialLtv) / 1e8;
        res.xt.approve(address(res.market), xtAmtToRedeem);
        res.ft.approve(address(res.market), ftAmtToRedeem);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
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
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut) / 2
        );

        uint128 underlyingAmtInForBuyFt = 9e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmt = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut) / 2
        );

        uint128 underlyingAmtToRedeem = xtAmt;
        uint128 xtAmtToRedeem = underlyingAmtToRedeem;
        uint128 ftAmtToRedeem = (underlyingAmtToRedeem *
            res.market.config().initialLtv) / 1e8;
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
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut) / 2
        );

        uint128 underlyingAmtInForBuyFt = 9e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmt = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut) / 2
        );

        uint128 underlyingAmtToRedeem = xtAmt;
        uint128 xtAmtToRedeem = underlyingAmtToRedeem;
        uint128 ftAmtToRedeem = (underlyingAmtToRedeem *
            res.market.config().initialLtv) / 1e8;
        res.xt.approve(address(res.market), xtAmtToRedeem);
        res.ft.approve(address(res.market), ftAmtToRedeem);

        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
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
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut)
        );
        uint128 collateralAmtIn = 1e18;
        res.collateral.mint(sender, collateralAmtIn);
        res.xt.approve(address(outer), xtAmtIn);
        bytes memory callbackData = abi.encode(collateralAmtIn);
        outer.leverageByXt(sender, xtAmtIn, callbackData);
        vm.stopPrank();
    }

    //TODO: test case for redemption
}

contract MockOuter is IFlashLoanReceiver {
    DeployUtils.Res res;

    constructor(DeployUtils.Res memory _res) {
        res = _res;
    }

    function executeOperation(
        address sender,
        IERC20 asset,
        uint256 amount,
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
