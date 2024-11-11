// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import "../contracts/core/storage/TermMaxStorage.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter, SwapInput} from "../contracts/router/ITermMaxRouter.sol";



contract TermMaxRouterTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address sender = vm.randomAddress();
    address receiver = sender;

    address treasurer = vm.randomAddress();
    string testdata;
    ITermMaxRouter router;

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


        router = DeployUtils.deployRouter(deployer);
        router.setMarketWhitelist(address(res.market), true);
        router.setSwapperWhitelist(address(res.collateral), true);
        router.togglePause(false);
        

        vm.stopPrank();
    }

    function testSwapExactTokenForFt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 0e8;
        res.underlying.mint(sender, underlyingAmtIn);


        res.underlying.approve(address(router), underlyingAmtIn);
        uint256 netOut = router.swapExactTokenForFt(receiver, res.market, underlyingAmtIn, minTokenOut);

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
        uint256 netOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);
       
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
        res.underlying.approve(address(res.market), underlyingAmtInForBuyFt);
        uint128 ftAmtIn = uint128(
            res.market.buyFt(underlyingAmtInForBuyFt, minFtOut)
        );
        uint128 minTokenOut = 0e8;

        res.ft.approve(address(router), ftAmtIn);
        uint256 netOut = router.swapExactFtForToken(receiver, res.market, ftAmtIn, minTokenOut);

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
        res.underlying.approve(address(res.market), underlyingAmtInForBuyXt);
        uint128 xtAmtIn = uint128(
            res.market.buyXt(underlyingAmtInForBuyXt, minXTOut)
        );
        uint128 minTokenOut = 0e8;

        res.xt.approve(address(router), xtAmtIn);
        uint256 netOut = router.swapExactXtForToken(receiver, res.market, xtAmtIn, minTokenOut);

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


        uint128 underlyingAmtInForBuyXt = 100e8;
        uint128 minXTOut = 1e8;
        uint256 minCollAmt = 100e8 * 2;
        res.underlying.mint(sender, underlyingAmtInForBuyXt);
        res.underlying.approve(address(router), underlyingAmtInForBuyXt);

        bytes memory swapData = abi.encodeWithSelector(
            IMintableERC20.mint.selector,
            address(router),
            minCollAmt
        );
        SwapInput memory swapInput = SwapInput(
            address(res.collateral), // swapper
            swapData,
            res.underlying,
            res.collateral
        );

        router.leverageFromToken(receiver, res.market, underlyingAmtInForBuyXt, minCollAmt, minXTOut, swapInput);

        vm.stopPrank();

    }

    function testLeverageFromXt() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        uint128 minTokenOut = 1e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(router), underlyingAmtIn);
        uint256 netXtOut = router.swapExactTokenForXt(receiver, res.market, underlyingAmtIn, minTokenOut);
        uint256 xtInAmt = netXtOut;

        uint256 minCollAmt = 100e8 * 2;
        bytes memory swapData = abi.encodeWithSelector(
            IMintableERC20.mint.selector,
            address(router),
            minCollAmt
        );
        SwapInput memory swapInput = SwapInput(
            address(res.collateral), // swapper
            swapData,
            res.underlying,
            res.collateral
        );
        res.xt.approve(address(router), xtInAmt);
        router.leverageFromXt(receiver, res.market, xtInAmt, minCollAmt, swapInput);

        vm.stopPrank();
    }


    function testBorrowTokenFromCollateral() public {
        vm.startPrank(sender);

        uint128 collateralAmtIn = 100e8;
        uint128 debtAmt = 95e8;
        uint128 borrowAmt = 1e8;
        res.collateral.mint(sender, collateralAmtIn);
        res.collateral.approve(address(router), collateralAmtIn);

        (uint256 gtId) = router.borrowTokenFromCollateral(receiver, res.market, collateralAmtIn, debtAmt, borrowAmt);

        (
            address final_owner,
            uint128 final_debtAmt,
            uint128 final_ltv,
            bytes memory final_collateralData
        ) = res.gt.loanInfo(gtId);
        assert(final_owner == receiver);
        assert(final_debtAmt <= debtAmt);
        assert(abi.decode(final_collateralData, (uint256)) == collateralAmtIn);

        vm.stopPrank();
    }

}
