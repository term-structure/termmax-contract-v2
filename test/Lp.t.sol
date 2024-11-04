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

        uint amount = 10000e8;
        res.underlying.mint(deployer, amount);
        res.underlying.approve(address(res.market), amount);
        res.market.provideLiquidity(amount);

        vm.stopPrank();
    }

    function testProvideLiquidity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
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
        res.underlying.approve(address(res.market), underlyingAmtInFirstTime);
        (uint128 lpFtOutAmtFirstTime, uint128 lpXtOutAmtFirstTime) = res
            .market
            .provideLiquidity(underlyingAmtInFirstTime);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.provideLiquidityTwice.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            lpFtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.provideLiquidityTwice.output.lpFtAmount"
                    )
                )
        );
        assert(
            lpXtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.provideLiquidityTwice.output.lpXtAmount"
                    )
                )
        );
        assert(res.lpFt.balanceOf(sender) == lpFtOutAmtFirstTime + lpFtOutAmt);
        assert(res.lpXt.balanceOf(sender) == lpXtOutAmtFirstTime + lpXtOutAmt);

        vm.stopPrank();
    }

    function testProvideLiquidityBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity - 1);
        res.market.provideLiquidity(underlyingAmtIn);

        vm.stopPrank();
    }

    function testProvideLiquidityAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        res.market.provideLiquidity(underlyingAmtIn);

        vm.stopPrank();
    }

    function testWithdrawLp() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        (uint128 ftOutAmt, uint128 xtOutAmt) = res.market.withdrawLp(
            lpFtOutAmt,
            lpXtOutAmt
        );

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.withdrawLp.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            ftOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.withdrawLp.output.lpFtAmount"
                    )
                )
        );
        assert(
            xtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.withdrawLp.output.lpXtAmount"
                    )
                )
        );
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.xt.balanceOf(sender) == xtOutAmt);

        vm.stopPrank();
    }

    function testWithdrawLpWhenFtIsMore() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        (uint128 ftOutAmt, uint128 xtOutAmt) = res.market.withdrawLp(
            lpFtOutAmt,
            lpXtOutAmt / 2
        );

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.withdrawLpWhenFtIsMore.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            ftOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.withdrawLpWhenFtIsMore.output.lpFtAmount"
                    )
                )
        );
        assert(
            xtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.withdrawLpWhenFtIsMore.output.lpXtAmount"
                    )
                )
        );
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.xt.balanceOf(sender) == xtOutAmt);

        vm.stopPrank();
    }

    function testWithdrawLpWhenXtIsMore() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        (uint128 ftOutAmt, uint128 xtOutAmt) = res.market.withdrawLp(
            lpFtOutAmt,
            lpXtOutAmt / 2
        );

        StateChecker.MarketState memory expectedState = JSONLoader
            .getMarketStateFromJson(
                testdata,
                ".expected.withdrawLpWhenXtIsMore.contractState"
            );
        StateChecker.checkMarketState(res, expectedState);

        assert(
            ftOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.withdrawLpWhenXtIsMore.output.lpFtAmount"
                    )
                )
        );
        assert(
            xtOutAmt ==
                vm.parseUint(
                    vm.parseJsonString(
                        testdata,
                        ".expected.withdrawLpWhenXtIsMore.output.lpXtAmount"
                    )
                )
        );
        assert(res.ft.balanceOf(sender) == ftOutAmt);
        assert(res.xt.balanceOf(sender) == xtOutAmt);

        vm.stopPrank();
    }

    function testWithdrawLpBeforeMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        vm.warp(res.market.config().maturity - 1);
        res.market.withdrawLp(
            lpFtOutAmt,
            lpXtOutAmt
        );

        vm.stopPrank();
    }

    function testWithdrawLpAfterMaturity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        vm.warp(res.market.config().maturity);
        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.MarketWasClosed.selector)
        );
        res.market.withdrawLp(
            lpFtOutAmt,
            lpXtOutAmt
        );

        vm.stopPrank();
    }
}
