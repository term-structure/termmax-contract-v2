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

    TokenPairConfig tokenPairConfig;
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
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        uint32 maxLtv = 0.89e8;
        uint32 liquidationLtv = 0.9e8;

        tokenPairConfig = JSONLoader.getTokenPairConfigFromJson(treasurer, testdata, ".tokenPairConfig");
        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        res = DeployUtils.deployMarket(deployer, tokenPairConfig, marketConfig, maxLtv, liquidationLtv);
        vm.warp(vm.parseUint(vm.parseJsonString(testdata, ".currentTime")));

        // update oracle
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.underlyingOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai")
        );

        uint amount = 150e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.tokenPair), amount);
        res.tokenPair.mintFtAndXt(deployer, amount);
        res.ft.transfer(address(res.market), amount);
        res.xt.transfer(address(res.market), amount);

        adapter = new MockSwapAdapter(pool);

        router = DeployUtils.deployRouter(deployer);
        router.setTokenPairWhitelist(address(res.tokenPair), true);
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
        router.swapExactTokenForFt(receiver, res.market, amount, 0);

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

        vm.expectRevert(abi.encodeWithSelector(ITermMaxRouter.MarketNotWhitelisted.selector, address(res.market)));
        router.swapExactTokenForFt(receiver, res.market, amount, 0);
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
            LoanUtils.fastMintGt(res, deployer, debtAmt, collateralAmt);
            LoanUtils.fastMintGt(res, deployer, debtAmt, collateralAmt);
            vm.stopPrank();

            vm.startPrank(sender);

            uint128 amount = 1000e8;
            res.underlying.mint(sender, amount * 2);
            res.underlying.approve(address(router), amount);
            router.swapExactTokenForFt(receiver, res.market, amount, 0);

            res.collateral.mint(sender, 5e18);
            (gtIdArray[0], ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
            (gtIdArray[1], ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

            vm.stopPrank();
        }

        (IERC20[6] memory tokens, uint256[6] memory balances, address gtAddr, uint256[] memory gtIds) = router
            .assetsWithERC20Collateral(res.market, sender);

        assertEq(address(res.ft), address(tokens[0]));
        assertEq(res.ft.balanceOf(sender), balances[0]);
        assertEq(address(res.xt), address(tokens[1]));
        assertEq(res.xt.balanceOf(sender), balances[1]);
        assertEq(address(res.collateral), address(tokens[2]));
        assertEq(res.collateral.balanceOf(sender), balances[2]);
        assertEq(address(res.underlying), address(tokens[3]));
        assertEq(res.underlying.balanceOf(sender), balances[3]);

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

        uint expectOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyFt.output.netOut"));
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
        uint256 netOut = router.swapExactTokenForFt(receiver, res.market, underlyingAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader.getMarketStateFromJson(
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

        uint128 underlyingAmtIn = 5e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        uint expectOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testBuyXt.output.netOut"));
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

        uint256 netOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader.getMarketStateFromJson(
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
        uint128 ftAmtIn = uint128(router.swapExactTokenForFt(receiver, res.market, underlyingAmtInForBuyFt, minFtOut));
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(router), ftAmtIn);

        uint expectOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellFt.output.netOut"));
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
        uint256 netOut = router.swapExactFtForToken(receiver, res.market, ftAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader.getMarketStateFromJson(
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

        uint128 underlyingAmtInForBuyXt = 5e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(router), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(router.swapExactTokenForXt(receiver, res.market, underlyingAmtInForBuyXt, minXTOut));
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(router), xtAmtIn);

        uint expectOut = vm.parseUint(vm.parseJsonString(testdata, ".expected.testSellXt.output.netOut"));
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
        uint256 netOut = router.swapExactXtForToken(receiver, res.market, xtAmtIn, minTokenOut);

        StateChecker.MarketState memory expectedState = JSONLoader.getMarketStateFromJson(
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
        res.underlying.approve(address(router), underlyingAmtInForBuyXt + tokenInAmt);

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(address(adapter), address(res.underlying), address(res.collateral), abi.encode(minCollAmt));

        (uint gtId, ) = router.leverageFromToken(
            receiver,
            res.market,
            tokenInAmt,
            underlyingAmtInForBuyXt,
            maxLtv,
            minXTOut,
            units
        );
        (address owner, , , bytes memory collateralData) = res.gt.loanInfo(gtId);
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
        uint256 netXtOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);
        uint256 xtInAmt = netXtOut;

        uint256 minCollAmt = 100e18 * 2;
        uint tokenAmtIn = 10e18;
        uint256 maxLtv = 0.8e8;
        res.underlying.mint(sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(address(adapter), address(res.underlying), address(res.collateral), abi.encode(minCollAmt));

        res.xt.approve(address(router), xtInAmt);
        uint256 gtId = router.leverageFromXt(receiver, res.market, xtInAmt, tokenAmtIn, maxLtv, units);
        (address owner, , , bytes memory collateralData) = res.gt.loanInfo(gtId);
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
        uint256 netXtOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);
        uint256 xtInAmt = netXtOut;

        uint256 minCollAmt = (xtInAmt * 1.2e10) / 2000;
        console.log("xtInAmt", xtInAmt);
        uint tokenAmtIn = 1e18;
        uint256 maxLtv = 0.8e8;
        res.underlying.mint(sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(address(adapter), address(res.underlying), address(res.collateral), abi.encode(minCollAmt));

        res.xt.approve(address(router), xtInAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxRouter.LtvBiggerThanExpected.selector,
                uint128(maxLtv),
                uint128(0.83333333e8)
            )
        );
        router.leverageFromXt(receiver, res.market, xtInAmt, tokenAmtIn, maxLtv, units);
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
        uint256 netXtOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);
        uint256 xtInAmt = netXtOut;

        uint256 minCollAmt = 10e18;
        uint tokenAmtIn = 1e18;
        uint256 maxLtv = 0.8e8;
        res.underlying.mint(sender, tokenAmtIn);
        res.underlying.approve(address(router), tokenAmtIn);

        SwapUnit[] memory units = new SwapUnit[](1);
        units[0] = SwapUnit(address(adapter), address(res.underlying), address(res.collateral), abi.encode(minCollAmt));

        res.xt.approve(address(router), xtInAmt);

        vm.expectRevert(abi.encodeWithSelector(ITermMaxRouter.AdapterNotWhitelisted.selector, address(adapter)));
        router.leverageFromXt(receiver, res.market, xtInAmt, tokenAmtIn, maxLtv, units);
        vm.stopPrank();
    }

    function testBorrowTokenFromCollateral() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 100e18 * 2;
        uint128 debtAmt = 20e8;
        uint128 borrowAmt = 1e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(router), collateralAmtIn);

        uint256 gtId = router.borrowTokenFromCollateral(receiver, res.market, collateralAmtIn, debtAmt, borrowAmt);

        (address final_owner, uint128 final_debtAmt, , bytes memory final_collateralData) = res.gt.loanInfo(gtId);
        assert(final_owner == receiver);
        assert(final_debtAmt <= debtAmt);
        assert(abi.decode(final_collateralData, (uint256)) == collateralAmtIn);

        vm.stopPrank();
    }

    function testRepay() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        res.underlying.mint(sender, debtAmt);

        res.underlying.approve(address(router), debtAmt);
        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        StateChecker.TokenPairState memory state = StateChecker.getTokenPairState(res);
        bool byUnderlying = true;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        router.repay(res.market, gtId, debtAmt);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);
        state.underlyingReserve += debtAmt;
        state.collateralReserve -= collateralAmt;
        StateChecker.checkTokenPairState(res, state);

        assert(collateralBalanceAfter - collateralBalanceBefore == collateralAmt);
        assert(underlyingBalanceAfter + debtAmt == underlyingBalanceBefore);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testRepayFromFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        // get FT token
        uint128 underlyingAmtInForBuyFt = 100e8;
        uint128 minXTOut = 0e8;
        res.underlying.mint(sender, underlyingAmtInForBuyFt);
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        res.market.buyFt(underlyingAmtInForBuyFt, minXTOut);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);
        uint ftInGtBefore = res.ft.balanceOf(address(res.gt));
        StateChecker.TokenPairState memory state = StateChecker.getTokenPairState(res);

        res.ft.approve(address(router), debtAmt);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        router.repayFromFt(res.market, gtId, debtAmt);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint ftInGtAfter = res.ft.balanceOf(address(res.gt));
        state.collateralReserve -= collateralAmt;
        StateChecker.checkTokenPairState(res, state);
        assert(ftInGtAfter - debtAmt == ftInGtBefore);
        assert(collateralBalanceAfter - collateralBalanceBefore == collateralAmt);
        assert(ftBalanceAfter + debtAmt == ftBalanceBefore);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testRepayByTokenThroughFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        res.underlying.mint(sender, debtAmt);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);

        res.underlying.approve(address(router), debtAmt);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, debtAmt, byUnderlying);
        router.repayByTokenThroughFt(sender, res.market, gtId, debtAmt, debtAmt);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(underlyingBalanceAfter > underlyingBalanceBefore - debtAmt);
        assert(collateralBalanceAfter - collateralBalanceBefore == collateralAmt);

        assert(ftBalanceAfter == ftBalanceBefore);
        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);

        vm.stopPrank();
    }

    function testPartialRepayByTokenThroughFt() public {
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        uint repayAmtIn = debtAmt / 2;
        res.underlying.mint(sender, repayAmtIn);

        uint collateralBalanceBefore = res.collateral.balanceOf(sender);
        uint underlyingBalanceBefore = res.underlying.balanceOf(sender);
        uint ftBalanceBefore = res.ft.balanceOf(sender);

        res.underlying.approve(address(router), repayAmtIn);

        bool byUnderlying = false;
        vm.expectEmit();
        emit IGearingToken.Repay(gtId, 5125201060, byUnderlying);
        router.repayByTokenThroughFt(sender, res.market, gtId, repayAmtIn, repayAmtIn);

        uint collateralBalanceAfter = res.collateral.balanceOf(sender);
        uint ftBalanceAfter = res.ft.balanceOf(sender);
        uint underlyingBalanceAfter = res.underlying.balanceOf(sender);

        assert(underlyingBalanceAfter == underlyingBalanceBefore - repayAmtIn);
        assert(collateralBalanceAfter == collateralBalanceBefore);

        assert(ftBalanceAfter == ftBalanceBefore);

        vm.stopPrank();
    }

    function testFlashRepay() public {
        vm.startPrank(sender);

        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        uint256 collateralValue = 2000e8;

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

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
        assert(underlyingBalanceAfter == underlyingBalanceBefore + collateralValue - debtAmt);

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);
        vm.stopPrank();
    }

    function testFlashRepayByFt() public {
        vm.startPrank(sender);

        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        uint256 collateralValue = 2000e8;

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

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
        assert(underlyingBalanceAfter >= underlyingBalanceBefore);

        vm.expectRevert(abi.encodePacked(bytes4(keccak256("ERC721NonexistentToken(uint256)")), gtId));
        res.gt.loanInfo(gtId);
        vm.stopPrank();
    }

    function testFlashRepayWithoutApprove() public {
        vm.startPrank(sender);

        uint128 debtAmt = 1000e8;
        uint256 collateralAmt = 1e18;
        uint256 collateralValue = 2000e8;

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

        uint256 minUnderlyingAmt = collateralValue;
        vm.expectRevert();
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

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);

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
            abi.encodeWithSignature("ERC721IncorrectOwner(address,uint256,address)", deployer, gtId, sender)
        );
        router.flashRepayFromColl(sender, res.market, gtId, true, units);
    }

    function testExecuteFromInvalidGt() public {
        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(ITermMaxRouter.TokenPairNotWhitelisted.selector, sender));
        router.executeOperation(sender, res.underlying, 10e8, "");

        FakeGt fg = new FakeGt(sender);

        vm.expectRevert(abi.encodeWithSelector(ITermMaxRouter.TokenPairNotWhitelisted.selector, fg.tokenPairAddr()));
        vm.prank(address(fg));
        router.executeOperation(res.underlying, 10e8, address(res.collateral), "", "");

        fg = new FakeGt(address(res.tokenPair));

        vm.expectRevert(abi.encodeWithSelector(ITermMaxRouter.GtNotWhitelisted.selector, address(fg)));
        vm.prank(address(fg));
        router.executeOperation(res.underlying, 10e8, address(res.collateral), "", "");
    }

    function testRedeem() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        (uint256 gtId, uint128 ftOutAmt) = res.tokenPair.issueFt(debtAmt, collateralData);
        uint128 repayAmt = debtAmt / 2;
        res.underlying.mint(sender, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);
        res.gt.repay(gtId, repayAmt, true);

        vm.warp(tokenPairConfig.maturity + Constants.LIQUIDATION_WINDOW);
        (IMintableERC20 ft, , , , IERC20 underlying) = res.tokenPair.tokens();
        uint propotion = (ftOutAmt * Constants.DECIMAL_BASE_SQ) / ft.totalSupply();
        uint underlyingAmt = (underlying.balanceOf(address(res.tokenPair)) * propotion) / Constants.DECIMAL_BASE_SQ;
        uint feeAmt = (underlyingAmt * tokenPairConfig.redeemFeeRatio) / Constants.DECIMAL_BASE;
        uint deliveryAmt = (res.collateral.balanceOf(address(res.gt)) * propotion) / Constants.DECIMAL_BASE_SQ;
        bytes memory deliveryData = abi.encode(deliveryAmt);
        res.ft.approve(address(router), ftOutAmt);

        StateChecker.TokenPairState memory state = StateChecker.getTokenPairState(res);
        vm.expectEmit();
        emit ITermMaxMarket.Redeem(
            address(router),
            uint128(propotion),
            uint128(underlyingAmt - feeAmt),
            uint128(feeAmt),
            deliveryData
        );
        router.redeem(receiver, res.tokenPair, ftOutAmt);
        state.collateralReserve -= deliveryAmt;
        state.underlyingReserve -= underlyingAmt;
        StateChecker.checkTokenPairState(res, state);

        vm.stopPrank();
    }

    function testRevertByCanNotRedeemBeforeFinalLiquidationDeadline() public {
        vm.startPrank(sender);
        uint128 debtAmt = 100e8;
        uint256 collateralAmt = 1e18;
        res.collateral.mint(sender, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);
        (uint256 gtId, uint128 ftOutAmt) = res.tokenPair.issueFt(debtAmt, collateralData);
        uint128 repayAmt = debtAmt / 2;
        res.underlying.mint(sender, repayAmt);
        res.underlying.approve(address(res.gt), repayAmt);
        res.gt.repay(gtId, repayAmt, true);

        res.ft.approve(address(router), ftOutAmt);
        vm.warp(tokenPairConfig.maturity);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.CanNotRedeemBeforeFinalLiquidationDeadline.selector,
                tokenPairConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        router.redeem(receiver, res.tokenPair, ftOutAmt);

        vm.warp(tokenPairConfig.maturity - Constants.SECONDS_IN_DAY);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITermMaxMarket.CanNotRedeemBeforeFinalLiquidationDeadline.selector,
                tokenPairConfig.maturity + Constants.LIQUIDATION_WINDOW
            )
        );
        router.redeem(receiver, res.tokenPair, ftOutAmt);

        vm.stopPrank();
    }

    function testAddCollateral() public {
        uint128 debtAmt = 1700e8;
        uint256 collateralAmt = 1e18;
        uint256 addedCollateral = 0.1e18;

        vm.startPrank(sender);

        (uint256 gtId, ) = LoanUtils.fastMintGt(res, sender, debtAmt, collateralAmt);
        vm.stopPrank();
        // Add collateral by third address
        address thirdPeople = vm.randomAddress();
        res.collateral.mint(thirdPeople, addedCollateral);
        vm.startPrank(thirdPeople);

        res.collateral.approve(address(router), addedCollateral);

        StateChecker.TokenPairState memory state = StateChecker.getTokenPairState(res);

        router.addCollateral(res.market, gtId, addedCollateral);

        state.collateralReserve += addedCollateral;
        StateChecker.checkTokenPairState(res, state);
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
}

contract FakeGt {
    address public tokenPairAddr;

    constructor(address tokenPair) {
        tokenPairAddr = tokenPair;
    }
}
