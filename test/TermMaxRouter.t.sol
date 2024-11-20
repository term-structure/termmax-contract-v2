// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";

import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter, SwapUnit} from "../contracts/router/ITermMaxRouter.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {ISwapAdapter, MockSwapAdapter} from "../contracts/test/MockSwapAdapter.sol";

contract TermMaxRouterTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address sender = vm.randomAddress();
    address receiver = sender;

    address treasurer = vm.randomAddress();
    string testdata;
    ITermMaxRouter router;

    address pool = vm.randomAddress();
    ISwapAdapter adapter;

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

        adapter = new MockSwapAdapter(pool);

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

        router = DeployUtils.deployRouter(deployer);
        router.setMarketWhitelist(address(res.market), true);
        router.setSwapperWhitelist(address(res.collateral), true);
        router.setSwapperWhitelist(address(adapter), true);
        router.togglePause(false);

        vm.stopPrank();
    }

    function testSwapExactTokenForFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);

        res.underlying.approve(address(router), underlyingAmtIn);
        uint256 netOut = router.swapExactTokenForFt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut
        );

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

    function testSwapExactTokenForXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        uint256 netOut = router.swapExactTokenForXt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut
        );

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

    function testSwapExactFtForToken() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minFtOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(router), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            router.swapExactTokenForFt(
                receiver,
                res.market,
                underlyingAmtInForBuyFt,
                minFtOut
            )
        );
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(router), ftAmtIn);
        uint256 netOut = router.swapExactFtForToken(
            receiver,
            res.market,
            ftAmtIn,
            minTokenOut
        );

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

    function testSwapExactXtForToken() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(router), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            router.swapExactTokenForXt(
                receiver,
                res.market,
                underlyingAmtInForBuyXt,
                minXTOut
            )
        );
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(router), xtAmtIn);
        uint256 netOut = router.swapExactXtForToken(
            receiver,
            res.market,
            xtAmtIn,
            minTokenOut
        );

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

    function testLeverageFromToken() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInForBuyXt = 5e8;
        uint256 tokenInAmt = 100e8;
        uint128 minXTOut = 0e8;
        uint256 minCollAmt = 1e18;
        uint256 maxLtv = 0.8e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt + tokenInAmt);
        res.underlying.approve(
            address(router),
            underlyingAmtInForBuyXt + tokenInAmt
        );

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(
            address(adapter),
            address(res.underlying),
            address(res.collateral),
            abi.encode(minCollAmt)
        );

        router.leverageFromToken(
            receiver,
            res.market,
            tokenInAmt,
            underlyingAmtInForBuyXt,
            maxLtv,
            minXTOut,
            units
        );

        vm.stopPrank();
    }

    function testLeverageFromXt() public {
        vm.startPrank(sender);
        uint128 underlyingAmtIn = 10e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        uint256 netXtOut = router.swapExactTokenForXt(
            receiver,
            res.market,
            underlyingAmtIn,
            minTokenOut
        );
        uint256 xtInAmt = netXtOut;

        uint256 minCollAmt = 100e18 * 2;
        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;
        res.underlying.mint(sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(
            address(adapter),
            address(res.underlying),
            address(res.collateral),
            abi.encode(minCollAmt)
        );

        res.xt.approve(address(router), xtInAmt);
        uint256 gtId = router.leverageFromXt(
            receiver,
            res.market,
            xtInAmt,
            tokenAmtIn,
            maxLtv,
            units
        );
        (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralData
        ) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        vm.stopPrank();
    }

    function testBorrowTokenFromCollateral() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 100e18 * 2;
        uint128 debtAmt = 20e8;
        uint128 borrowAmt = 1e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(router), collateralAmtIn);

        uint256 gtId = router.borrowTokenFromCollateral(
            receiver,
            res.market,
            collateralAmtIn,
            debtAmt,
            borrowAmt
        );

        (
            address final_owner,
            uint128 final_debtAmt,
            ,
            bytes memory final_collateralData
        ) = res.gt.loanInfo(gtId);
        assert(final_owner == receiver);
        assert(final_debtAmt <= debtAmt);
        assert(abi.decode(final_collateralData, (uint256)) == collateralAmtIn);

        vm.stopPrank();
    }

    function testFlashRepay() public {
        vm.startPrank(sender);

        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        uint256 collateralValue = 2000e8;

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        uint256 minUnderlyingAmt = collateralValue;

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(
            address(adapter),
            address(res.collateral),
            address(res.underlying),
            abi.encode(minUnderlyingAmt)
        );
        res.collateral.approve(address(router), collateralAmt);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);

        router.flashRepayFromColl(sender, res.market, gtId, units);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(collateralBalanceBefore == collateralBalanceAfter);
        assert(
            underlyingBalanceAfter ==
                underlyingBalanceBefore + collateralValue - debtAmt
        );

        vm.stopPrank();
    }

    /** */
    function testProvideLiquidity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);

        // uint expectLpFtOutAmt = vm.parseUint(
        //     vm.parseJsonString(
        //         testdata,
        //         ".expected.provideLiquidity.output.lpFtAmount"
        //     )
        // );
        // uint expectLpXtOutAmt = vm.parseUint(
        //     vm.parseJsonString(
        //         testdata,
        //         ".expected.provideLiquidity.output.lpXtAmount"
        //     )
        // );

        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.provideLiquidity.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            lpFtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.provideLiquidity.output.lpFtAmount"
                    )
                )
        );
        assert(
            lpXtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.provideLiquidity.output.lpXtAmount"
                    )
                )
        );
        assert(res.lpFt.balanceOf(sender) == lpFtOutAmt);
        assert(res.lpXt.balanceOf(sender) == lpXtOutAmt);

        vm.stopPrank();
    }

    function testProvideLiquidityTwice() public {
        vm.startPrank(sender);

        uint128 underlyingAmtInFirstTime = 100e8;
        res.underlying.mint(sender, underlyingAmtInFirstTime);
        res.underlying.approve(address(router), underlyingAmtInFirstTime);
        (uint128 lpFtOutAmtFirstTime, uint128 lpXtOutAmtFirstTime) = router
            .provideLiquidity(receiver, res.market, underlyingAmtInFirstTime);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);

        uint expectLpFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.provideLiquidityTwice.output.lpFtAmount"
            )
        );
        uint expectLpXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.provideLiquidityTwice.output.lpXtAmount"
            )
        );

        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.provideLiquidityTwice.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(lpFtOutAmt == expectLpFtOutAmt);
        assert(lpXtOutAmt == expectLpXtOutAmt);
        assert(res.lpFt.balanceOf(sender) == lpFtOutAmtFirstTime + lpFtOutAmt);
        assert(res.lpXt.balanceOf(sender) == lpXtOutAmtFirstTime + lpXtOutAmt);

        vm.stopPrank();
    }

    function testProvideLiquidityBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        vm.warp(res.market.config().maturity - 1);
        router.provideLiquidity(receiver, res.market, underlyingAmtIn);

        vm.stopPrank();
    }

    function testProvideLiquidityAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        router.provideLiquidity(receiver, res.market, underlyingAmtIn);

        vm.stopPrank();
    }

    function testWithdrawLp() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        res.lpFt.approve(address(router), lpFtOutAmt);
        res.lpXt.approve(address(router), lpXtOutAmt);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.withdrawLp.contractState"
            );
        uint expectFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLp.output.lpFtAmount"
            )
        );
        uint expectXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLp.output.lpXtAmount"
            )
        );

        (uint256 ftOutAmt, uint256 xtOutAmt) = router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            lpFtOutAmt,
            lpXtOutAmt,
            0,
            0
        );

        StateChecker.checkMarketState(res, expectedState);

        assert(ftOutAmt == expectFtOutAmt);
        assert(xtOutAmt == expectXtOutAmt);
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.xt.balanceOf(sender) == xtOutAmt);

        vm.stopPrank();
    }

    function testRevertByLiquidityIsZeroAfterTransaction() public {
        vm.startPrank(deployer);

        uint lpFtBlance = res.lpFt.balanceOf(deployer);
        res.lpFt.approve(address(router), lpFtBlance);

        vm.expectRevert(
            abi.encodeWithSelector(
                TermMaxCurve.LiquidityIsZeroAfterTransaction.selector
            )
        );
        router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            uint128(lpFtBlance),
            0,
            0,
            0
        );

        uint lpXtBlance = res.lpXt.balanceOf(deployer);
        res.lpXt.approve(address(router), lpXtBlance);

        vm.expectRevert(
            abi.encodeWithSelector(
                TermMaxCurve.LiquidityIsZeroAfterTransaction.selector
            )
        );
        router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            0,
            uint128(lpXtBlance),
            0,
            0
        );

        vm.stopPrank();
    }

    function testWithdrawLpWhenFtIsMore() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        res.lpFt.approve(address(router), lpFtOutAmt);
        res.lpXt.approve(address(router), lpXtOutAmt);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.withdrawLpWhenFtIsMore.contractState"
            );
        uint expectFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLpWhenFtIsMore.output.lpFtAmount"
            )
        );
        uint expectXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLpWhenFtIsMore.output.lpXtAmount"
            )
        );

        (uint256 ftOutAmt, uint256 xtOutAmt) = router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            lpFtOutAmt,
            lpXtOutAmt / 2,
            0,
            0
        );

        StateChecker.checkMarketState(res, expectedState);

        assert(ftOutAmt == expectFtOutAmt);
        assert(xtOutAmt == expectXtOutAmt);
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.xt.balanceOf(sender) == xtOutAmt);

        vm.stopPrank();
    }

    function testWithdrawLpWhenXtIsMore() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        res.lpFt.approve(address(router), lpFtOutAmt);
        res.lpXt.approve(address(router), lpXtOutAmt);

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.withdrawLpWhenXtIsMore.contractState"
            );
        uint expectFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLpWhenXtIsMore.output.lpFtAmount"
            )
        );
        uint expectXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLpWhenXtIsMore.output.lpXtAmount"
            )
        );

        (uint256 ftOutAmt, uint256 xtOutAmt) = router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            lpFtOutAmt / 2,
            lpXtOutAmt,
            0,
            0
        );

        StateChecker.checkMarketState(res, expectedState);

        assert(ftOutAmt == expectFtOutAmt);
        assert(xtOutAmt == expectXtOutAmt);
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.xt.balanceOf(sender) == xtOutAmt);

        vm.stopPrank();
    }

    function testWithdrawLpBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        res.lpFt.approve(address(router), lpFtOutAmt);
        res.lpXt.approve(address(router), lpXtOutAmt);
        vm.warp(res.market.config().maturity - 1);
        router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            lpFtOutAmt,
            lpXtOutAmt,
            0,
            0
        );

        vm.stopPrank();
    }

    function testWithdrawLpAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );

        res.lpFt.approve(address(router), lpFtOutAmt);
        res.lpXt.approve(address(router), lpXtOutAmt);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        router.withdrawLiquidityToFtXt(
            receiver,
            res.market,
            lpFtOutAmt,
            lpXtOutAmt,
            0,
            0
        );

        vm.stopPrank();
    }

    function testRedeem() public {
        vm.startPrank(sender);
        // Add debt
        {
            uint128 debtAmt = 100e8;
            uint256 collateralAmt = 1e18;
            (uint256 gtId, ) = LoanUtils.fastMintGt(
                res,
                sender,
                debtAmt,
                collateralAmt
            );
            uint128 repayAmt = debtAmt / 10;
            res.ft.approve(address(res.gt), repayAmt);

            res.gt.repay(gtId, repayAmt, false);
        }
        // Do some swap
        {
            uint ftBalance = res.ft.balanceOf(sender);
            res.ft.approve(address(res.market), ftBalance);
            res.market.sellFt(uint128(ftBalance / 2), 0);

            uint lpXtBalance = res.lpXt.balanceOf(sender);
            res.lpXt.approve(address(res.market), lpXtBalance);

            res.market.withdrawLp(0, uint128(lpXtBalance / 2));
        }
        assert(res.lpFt.balanceOf(address(res.market)) > 0);
        assert(res.lpXt.balanceOf(address(res.market)) > 0);
        assert(res.ft.balanceOf(address(res.gt)) > 0);

        vm.warp(marketConfig.maturity + Constants.LIQUIDATION_WINDOW);

        uint256[4] memory senderBalances = _getBalancesAndApproveAll(
            res,
            sender
        );
        (
            uint128 propotion,
            uint128 underlyingAmt,
            uint128 feeAmt,
            bytes memory deliveryData
        ) = StateChecker.getRedeemPoints(res, marketConfig, senderBalances);
        uint underlyingBefore = res.underlying.balanceOf(sender);
        uint collateralBefore = res.collateral.balanceOf(sender);

        router.redeem(receiver, res.market, senderBalances, 0, 0);
        vm.stopPrank();
        uint underlyingAfter = res.underlying.balanceOf(sender);
        uint collateralAfter = res.collateral.balanceOf(sender);
        assertEq(underlyingBefore + underlyingAmt, underlyingAfter);
        assertEq(
            collateralBefore + abi.decode(deliveryData, (uint)),
            collateralAfter
        );

        vm.startPrank(deployer);
        uint[4] memory deployerBalances = _getBalancesAndApproveAll(
            res,
            deployer
        );
        (propotion, underlyingAmt, feeAmt, deliveryData) = StateChecker
            .getRedeemPoints(res, marketConfig, deployerBalances);

        router.redeem(receiver, res.market, deployerBalances, 0, 0);

        vm.startPrank(treasurer);

        uint[4] memory treasurerBalances = _getBalancesAndApproveAll(
            res,
            treasurer
        );
        (propotion, underlyingAmt, feeAmt, deliveryData) = StateChecker
            .getRedeemPoints(res, marketConfig, treasurerBalances);

        router.redeem(receiver, res.market, treasurerBalances, 0, 0);

        vm.stopPrank();

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        assert(state.ftReserve == 0);
        assert(state.xtReserve == 0);
        assert(state.lpFtReserve == 0);
        assert(state.lpXtReserve == 0);
    }

    function testRevertByCanNotRedeemBeforeFinalLiquidationDeadline() public {
        vm.startPrank(sender);
        // Add debt
        {
            uint128 debtAmt = 100e8;
            uint256 collateralAmt = 1e18;
            (uint256 gtId, ) = LoanUtils.fastMintGt(
                res,
                sender,
                debtAmt,
                collateralAmt
            );
            uint128 repayAmt = debtAmt / 10;
            res.ft.approve(address(res.gt), repayAmt);

            res.gt.repay(gtId, repayAmt, false);
        }
        // Do some swap
        {
            uint ftBalance = res.ft.balanceOf(sender);
            res.ft.approve(address(res.market), ftBalance);
            res.market.sellFt(uint128(ftBalance / 2), 0);

            uint lpXtBalance = res.lpXt.balanceOf(sender);
            res.lpXt.approve(address(res.market), lpXtBalance);

            res.market.withdrawLp(0, uint128(lpXtBalance / 2));
        }

        assert(res.lpFt.balanceOf(address(res.market)) > 0);
        assert(res.lpXt.balanceOf(address(res.market)) > 0);
        assert(res.ft.balanceOf(address(res.gt)) > 0);

        uint[4] memory balances = _getBalancesAndApproveAll(res, sender);

        vm.warp(marketConfig.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket
                    .CanNotRedeemBeforeFinalLiquidationDeadline
                    .selector,
                marketConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        router.redeem(receiver, res.market, balances, 0, 0);

        vm.warp(marketConfig.maturity - Constants.SECONDS_IN_DAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket
                    .CanNotRedeemBeforeFinalLiquidationDeadline
                    .selector,
                marketConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        router.redeem(receiver, res.market, balances, 0, 0);

        vm.stopPrank();
    }

    function testAddCollateral() public {
        uint128 debtAmt = 1700e8;
        uint256 collateralAmt = 1e18;
        uint256 addedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        vm.stopPrank();
        // Add collateral by third address
        address thirdPeople = vm.randomAddress();
        res.collateral.mint(thirdPeople, addedCollateral);
        vm.startPrank(thirdPeople);

        res.collateral.approve(address(router), addedCollateral);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        router.addCollateral(res.market, gtId, addedCollateral);

        state.collateralReserve += addedCollateral;
        StateChecker.checkMarketState(res, state);
        assert(res.underlying.balanceOf(thirdPeople) == 0);
        assert(res.collateral.balanceOf(thirdPeople) == 0);

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt + addedCollateral == abi.decode(cd, (uint256)));
        vm.stopPrank();
        // Add collateral by self
        vm.startPrank(sender);

        res.collateral.mint(sender, addedCollateral);
        res.collateral.approve(address(res.gt), addedCollateral);

        res.gt.addCollateral(gtId, abi.encode(addedCollateral));
        vm.stopPrank();
    }

    function testRemoveCollateral() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        uint256 removedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        uint collateralBlanceBefore = res.collateral.balanceOf(sender);

        vm.expectEmit();
        emit IGearingToken.RemoveCollateral(
            gtId,
            abi.encode(collateralAmt - removedCollateral)
        );
        // TODO: need to authenticate router to control gt
        // router.removeCollateral(res.market, gtId, removedCollateral);
        res.gt.removeCollateral(gtId, abi.encode(removedCollateral));

        state.collateralReserve -= removedCollateral;
        StateChecker.checkMarketState(res, state);

        uint collateralBlanceAfter = res.collateral.balanceOf(sender);

        assert(
            collateralBlanceAfter - collateralBlanceBefore == removedCollateral
        );

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(gtId);
        assert(owner == sender);
        assert(d == debtAmt);
        assert(collateralAmt - removedCollateral == abi.decode(cd, (uint256)));

        vm.stopPrank();
    }

    function testMerge() public {
        uint40[3] memory debts = [100e8, 30e8, 5e8];
        uint64[3] memory collaterals = [1e18, 0.5e18, 0.05e18];

        vm.startPrank(sender);

        uint[] memory ids = new uint[](3);
        for (uint i = 0; i < ids.length; ++i) {
            (ids[i], ) = LoanUtils.fastMintGt(
                res,
                sender,
                debts[i],
                collaterals[i]
            );
        }
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        vm.expectEmit();
        uint newId = 4;
        emit IGearingToken.MergeGts(sender, newId, ids);
        // TODO: need to authenticate router to control gt
        // newId = router.mergeGt(res.market, ids);
        newId = res.gt.merge(ids);
        StateChecker.checkMarketState(res, state);

        (address owner, uint128 d, , bytes memory cd) = res.gt.loanInfo(newId);
        assert(owner == sender);
        assert(d == debts[0] + debts[1] + debts[2]);
        assert(
            collaterals[0] + collaterals[1] + collaterals[2] ==
                abi.decode(cd, (uint256))
        );
        for (uint i = 0; i < ids.length; i++) {
            vm.expectRevert(
                abi.encodePacked(
                    bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                    ids[i]
                )
            );
            res.gt.loanInfo(ids[i]);
        }

        vm.stopPrank();
    }

    function _getBalancesAndApproveAll(
        DeployUtils.Res memory res_,
        address user
    ) internal returns (uint[4] memory balances) {
        uint256[6] memory balancesArray = StateChecker.getUserBalances(
            res_,
            user
        );
        balances = [
            balancesArray[0],
            balancesArray[1],
            balancesArray[2],
            balancesArray[3]
        ];
        res_.ft.approve(address(router), balances[0]);
        res_.xt.approve(address(router), balances[1]);
        res_.lpFt.approve(address(router), balances[2]);
        res_.lpXt.approve(address(router), balances[3]);
    }
}
