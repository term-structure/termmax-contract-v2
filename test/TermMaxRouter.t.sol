// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve, IERC20} from "contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import "contracts/core/storage/TermMaxStorage.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter, SwapUnit} from "contracts/router/ITermMaxRouter.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {ISwapAdapter, MockSwapAdapter} from "contracts/test/MockSwapAdapter.sol";

contract TermMaxRouterTest is Test {
    address deployer = vm.randomAddress();

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address sender = vm.randomAddress();
    address receiver = sender;

    address treasurer = vm.randomAddress();
    string testdata;
    TermMaxRouter router;

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
        router.setAdapterWhitelist(address(adapter), true);
        router.togglePause(false);

        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(deployer);
        router.togglePause(true);

        assert(router.paused());

        uint128 amount = 10e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(router), amount);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("EnforcedPause()"))));
        router.provideLiquidity(receiver, res.market, amount);

        vm.stopPrank();
    }

    function testPauseWithoutPermisson() public {
        vm.startPrank(sender);

        vm.expectRevert();
        router.togglePause(true);

        vm.stopPrank();
    }

    function testSetMarketWhitelist() public {
        vm.startPrank(deployer);
        assert(router.marketWhitelist(address(res.market)) == true);
        vm.expectEmit();
        emit ITermMaxRouter.UpdateMarketWhiteList(address(res.market), false);
        router.setMarketWhitelist(address(res.market), false);

        uint128 amount = 10e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(router), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.MarketNotWhitelisted.selector,
                address(res.market)
            )
        );
        router.provideLiquidity(receiver, res.market, amount);
        assert(router.marketWhitelist(address(res.market)) == false);
        vm.stopPrank();
    }

    function testSetWhitelistWithoutPermisson() public {
        vm.startPrank(sender);

        vm.expectRevert();
        router.setMarketWhitelist(address(res.market), false);

        vm.expectRevert();
        router.setAdapterWhitelist(address(adapter), false);

        vm.stopPrank();
    }

    function testReadAssets() public {
        uint[2] memory gtIdArray;
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 0.1e18;
        {
            vm.startPrank(deployer);
            LoanUtils.fastMintGt(
                res,
                deployer,
                debtAmt,
                collateralAmt
            );
            LoanUtils.fastMintGt(
                res,
                deployer,
                debtAmt,
                collateralAmt
            );
            vm.stopPrank();
            
            vm.startPrank(sender);

            uint128 amount = 1000e8;
            res.underlying.mint(sender, amount * 2);
            res.underlying.approve(address(router), amount);
            router.provideLiquidity(receiver, res.market, amount);

            res.collateral.mint(sender, 5e18);
            (gtIdArray[0], ) = LoanUtils.fastMintGt(
                res,
                sender,
                debtAmt,
                collateralAmt
            );
            (gtIdArray[1], ) = LoanUtils.fastMintGt(
                res,
                sender,
                debtAmt,
                collateralAmt
            );

            vm.stopPrank();
        }

        (
            IERC20[6] memory tokens,
            uint256[6] memory balances,
            address gtAddr,
            uint256[] memory gtIds
        ) = router.assetsWithERC20Collateral(res.market, sender);

        assertEq(address(res.ft), address(tokens[0]));
        assertEq(res.ft.balanceOf(sender), balances[0]);
        assertEq(address(res.xt), address(tokens[1]));
        assertEq(res.xt.balanceOf(sender), balances[1]);
        assertEq(address(res.lpFt), address(tokens[2]));
        assertEq(res.lpFt.balanceOf(sender), balances[2]);
        assertEq(address(res.lpXt), address(tokens[3]));
        assertEq(res.lpXt.balanceOf(sender), balances[3]);
        assertEq(address(res.collateral), address(tokens[4]));
        assertEq(res.collateral.balanceOf(sender), balances[4]);
        assertEq(address(res.underlying), address(tokens[5]));
        assertEq(res.underlying.balanceOf(sender), balances[5]);

        assertEq(gtAddr, address(res.gt));
        assertEq(gtIdArray.length, gtIds.length);
        assertEq(gtIdArray[0], gtIds[0]);
        assertEq(gtIdArray[1], gtIds[1]);
    }

    function testSwapExactTokenForFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);

        res.underlying.approve(address(router), underlyingAmtIn);

        uint expectOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut")
        );
        vm.expectEmit();
        emit ITermMaxRouter.Swap(
            res.market,
            address(res.underlying),
            address(res.ft),
            sender,
            receiver,
            underlyingAmtIn,
            expectOut,
            minTokenOut
        );
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

        assert(netOut == expectOut);
        assert(res.ft.balanceOf(sender) == netOut);
        vm.stopPrank();
    }

    function testSwapExactTokenForXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        uint expectOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut")
        );
        vm.expectEmit();
        emit ITermMaxRouter.Swap(
            res.market,
            address(res.underlying),
            address(res.xt),
            sender,
            receiver,
            underlyingAmtIn,
            expectOut,
            minTokenOut
        );

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

        assert(netOut == expectOut);
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

        uint expectOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut")
        );
        vm.expectEmit();
        emit ITermMaxRouter.Swap(
            res.market,
            address(res.ft),
            address(res.underlying),
            sender,
            receiver,
            ftAmtIn,
            expectOut,
            minTokenOut
        );
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

        assert(netOut == expectOut);
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

        uint expectOut = vm.parseUint(
            vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut")
        );
        vm.expectEmit();
        emit ITermMaxRouter.Swap(
            res.market,
            address(res.xt),
            address(res.underlying),
            sender,
            receiver,
            xtAmtIn,
            expectOut,
            minTokenOut
        );
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

        assert(netOut == expectOut);
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

        (uint gtId, ) = router.leverageFromToken(
            receiver,
            res.market,
            tokenInAmt,
            underlyingAmtInForBuyXt,
            maxLtv,
            minXTOut,
            units
        );
        (address owner, , , bytes memory collateralData) = res.gt.loanInfo(
            gtId
        );
        assert(owner == sender);
        assert(minCollAmt == abi.decode(collateralData, (uint256)));
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
        (address owner, , , bytes memory collateralData) = res.gt.loanInfo(
            gtId
        );
        assert(owner == sender);
        assert(minCollAmt == abi.decode(collateralData, (uint256)));
        vm.stopPrank();
    }

    function testRevertWhenLtvBiggerThanMaxLtv() public {
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

        uint256 minCollAmt = (xtInAmt * 1e10) / 2000;
        uint tokenAmtIn = 1e18;
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.LtvBiggerThanExpected.selector,
                uint128(maxLtv),
                uint128(0.88e8)
            )
        );
        router.leverageFromXt(
            receiver,
            res.market,
            xtInAmt,
            tokenAmtIn,
            maxLtv,
            units
        );
        vm.stopPrank();
    }

    function testSetAdapterWhitelist() public {
        vm.startPrank(deployer);
        assert(router.adapterWhitelist(address(adapter)) == true);
        vm.expectEmit();
        emit ITermMaxRouter.UpdateSwapAdapterWhiteList(address(adapter), false);
        router.setAdapterWhitelist(address(adapter), false);

        assert(router.adapterWhitelist(address(adapter)) == false);
        vm.stopPrank();

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

        uint256 minCollAmt = 10e18;
        uint tokenAmtIn = 1e18;
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.AdapterNotWhitelisted.selector,
                address(adapter)
            )
        );
        router.leverageFromXt(
            receiver,
            res.market,
            xtInAmt,
            tokenAmtIn,
            maxLtv,
            units
        );
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

    function testRepay() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        res.underlying.mint(sender, debtAmt);

        res.underlying.approve(address(router), debtAmt);
        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        bool byUnderlying = true;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        router.repay(res.market, gtId, debtAmt);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);
        state.underlyingReserve += debtAmt;
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);

        assert(
            collateralBalanceAfter - collateralBalanceBefore == collateralAmt
        );
        assert(underlyingBalanceAfter + debtAmt == underlyingBalanceBefore);
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testRepayFromFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        // get FT token
        res.underlying.mint(sender, debtAmt);
        res.underlying.approve(address(res.market), debtAmt);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            debtAmt
        );
        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        res.market.withdrawLiquidity(lpFtOutAmt, lpXtOutAmt);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);
        uint ftInGtBefore = res.ft.balanceOf(address(res.gt));
        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );

        res.ft.approve(address(router), debtAmt);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        router.repayFromFt(res.market, gtId, debtAmt);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint ftInGtAfter = res.ft.balanceOf(address(res.gt));
        state.collateralReserve -= collateralAmt;
        StateChecker.checkMarketState(res, state);
        assert(ftInGtAfter - debtAmt == ftInGtBefore);
        assert(
            collateralBalanceAfter - collateralBalanceBefore == collateralAmt
        );
        assert(ftBalanceAfter + debtAmt == ftBalanceBefore);
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testRepayByTokenThroughFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );

        res.underlying.mint(sender, debtAmt);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);

        res.underlying.approve(address(router), debtAmt);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        router.repayByTokenThroughFt(
            sender,
            res.market,
            gtId,
            debtAmt,
            debtAmt
        );

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(underlyingBalanceAfter > underlyingBalanceBefore - debtAmt);
        assert(
            collateralBalanceAfter - collateralBalanceBefore == collateralAmt
        );

        assert(ftBalanceAfter == ftBalanceBefore);
        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testPartialRepayByTokenThroughFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(
            res,
            sender,
            debtAmt,
            collateralAmt
        );
        uint repayAmtIn = debtAmt/2;
        res.underlying.mint(sender, repayAmtIn);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);

        res.underlying.approve(address(router), repayAmtIn);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, 5095188345, byUnderlying);
        router.repayByTokenThroughFt(
            sender,
            res.market,
            gtId,
            repayAmtIn,
            repayAmtIn
        );

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(underlyingBalanceAfter == underlyingBalanceBefore - repayAmtIn);
        assert(
            collateralBalanceAfter  == collateralBalanceBefore
        );

        assert(ftBalanceAfter == ftBalanceBefore);

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
        res.gt.approve(address(router), gtId);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);

        router.flashRepayFromColl(sender, res.market, gtId, true, units);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(collateralBalanceBefore == collateralBalanceAfter);
        assert(
            underlyingBalanceAfter ==
                underlyingBalanceBefore + collateralValue - debtAmt
        );

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);
        vm.stopPrank();
    }

    function testFlashRepayByFt() public {
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
        res.gt.approve(address(router), gtId);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);

        router.flashRepayFromColl(sender, res.market, gtId, false, units);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(collateralBalanceBefore == collateralBalanceAfter);
        assert(
            underlyingBalanceAfter >=
                underlyingBalanceBefore
        );

        vm.expectRevert(
            abi.encodePacked(
                bytes4(keccak256("ERC721NonexistentToken(uint256)")),
                gtId
            )
        );
        res.gt.loanInfo(gtId);
        vm.stopPrank();
    }

    function testFlashRepayWithoutApprove() public {
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
        vm.expectRevert(
            
        );
        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(
            address(adapter),
            address(res.collateral),
            address(res.underlying),
            abi.encode(minUnderlyingAmt)
        );

        router.flashRepayFromColl(sender, res.market, gtId, true, units);
        vm.stopPrank();
    }

    function testFlashRepayFromRandomAddress() public {
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
        res.gt.approve(address(router), gtId);
        vm.stopPrank();
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSignature("ERC721IncorrectOwner(address,uint256,address)", deployer, gtId, sender));
        router.flashRepayFromColl(sender, res.market, gtId, true, units);
    }

    function testExecuteFromInvalidGt() public {
        vm.prank(sender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.MarketNotWhitelisted.selector,
                sender
            )
        );
        router.executeOperation(sender, res.underlying, 10e8, "");

        FakeGt fg = new FakeGt(sender);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.MarketNotWhitelisted.selector,
                fg.marketAddr()
            )
        );
        vm.prank(address(fg));
        router.executeOperation(
            res.underlying,
            10e8,
            address(res.collateral),
            "",
            ""
        );

        fg = new FakeGt(address(res.market));

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.GtNotWhitelisted.selector,
                address(fg)
            )
        );
        vm.prank(address(fg));
        router.executeOperation(
            res.underlying,
            10e8,
            address(res.collateral),
            "",
            ""
        );
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
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        router.provideLiquidity(receiver, res.market, underlyingAmtIn);

        vm.stopPrank();
    }

    function testWithdrawLiquidity() public {
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
                ".expected.withdrawLiquidity.contractState"
            );
        uint expectFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLiquidity.output.lpFtAmount"
            )
        );
        uint expectXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLiquidity.output.lpXtAmount"
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

    function testWithdrawLiquidityToToken(uint128 withdrawAmt) public {
        uint128 underlyingAmtIn = 100e8;
        vm.assume(withdrawAmt > 0 && withdrawAmt < 80e8);
        vm.startPrank(sender);

        
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = router.provideLiquidity(
            receiver,
            res.market,
            underlyingAmtIn
        );
        assert(lpFtOutAmt > withdrawAmt && lpXtOutAmt > withdrawAmt);

        res.lpFt.approve(address(router), withdrawAmt);
        res.lpXt.approve(address(router), withdrawAmt);

        router.withdrawLiquidityToToken(
            receiver,
            res.market,
            withdrawAmt,
            withdrawAmt,
            0
        );

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

    function testWithdrawLiquidityWhenFtIsMore() public {
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
                ".expected.withdrawLiquidityWhenFtIsMore.contractState"
            );
        uint expectFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLiquidityWhenFtIsMore.output.lpFtAmount"
            )
        );
        uint expectXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLiquidityWhenFtIsMore.output.lpXtAmount"
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

    function testWithdrawLiquidityWhenXtIsMore() public {
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
                ".expected.withdrawLiquidityWhenXtIsMore.contractState"
            );
        uint expectFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLiquidityWhenXtIsMore.output.lpFtAmount"
            )
        );
        uint expectXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.withdrawLiquidityWhenXtIsMore.output.lpXtAmount"
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

    function testWithdrawLiquidityBeforeMaturity() public {
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

    function testWithdrawLiquidityAfterMaturity() public {
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
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
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

            res.market.withdrawLiquidity(0, uint128(lpXtBalance / 2));
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

            res.market.withdrawLiquidity(0, uint128(lpXtBalance / 2));
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

    function testFixAuditIssue_2() public {
        vm.startPrank(deployer);
        res.lpFt.approve(address(router), res.lpFt.balanceOf(deployer));
        res.lpXt.approve(address(router), res.lpXt.balanceOf(deployer));
        router.withdrawLiquidityToFtXt(deployer, res.market, res.lpFt.balanceOf(deployer) - 1, res.lpXt.balanceOf(deployer) - 1, 0, 0);
        res.ft.transfer(address(res.market), res.ft.balanceOf(deployer));
        res.xt.transfer(address(res.market), res.xt.balanceOf(deployer));
        vm.stopPrank();
        vm.startPrank(sender);
        res.underlying.mint(sender, 1000e8);
        res.underlying.approve(address(res.market), 1000e8);
        res.market.provideLiquidity(1000e8);
        require(res.lpFt.balanceOf(sender) > 0);
        require(res.lpXt.balanceOf(sender) > 0);
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

contract FakeGt {
    address public marketAddr;

    constructor(address market) {
        marketAddr = market;
    }
}
