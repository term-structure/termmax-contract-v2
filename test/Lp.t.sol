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

contract LpTest is Test {
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

        vm.expectEmit();
        emit ITermMaxMarket.ProvideLiquidity(
            deployer,
            uint128(amount),
            uint128(amount * marketConfig.initialLtv),
            uint128(amount * Constants.DECIMAL_BASE)
        );
        res.market.provideLiquidity(amount);

        vm.stopPrank();
    }

    function testProvideLiquidity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        uint expectLpFtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.provideLiquidity.output.lpFtAmount"
            )
        );
        uint expectLpXtOutAmt = vm.parseUint(
            vm.parseJsonString(
                testdata,
                ".expected.provideLiquidity.output.lpXtAmount"
            )
        );
        vm.expectEmit();
        emit ITermMaxMarket.ProvideLiquidity(
            sender,
            underlyingAmtIn,
            uint128(expectLpFtOutAmt),
            uint128(expectLpXtOutAmt)
        );
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
        vm.expectEmit();
        emit ITermMaxMarket.ProvideLiquidity(
            sender,
            underlyingAmtIn,
            uint128(expectLpFtOutAmt),
            uint128(expectLpXtOutAmt)
        );
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
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

    function testProvideLiquidityRceiveNothing() public {
        vm.startPrank(deployer);
        res.lpFt.approve(address(res.market), res.lpFt.balanceOf(deployer));
        res.lpXt.approve(address(res.market), res.lpXt.balanceOf(deployer));
        res.market.withdrawLiquidity(uint128(res.lpFt.balanceOf(deployer) - 1), uint128(res.lpXt.balanceOf(deployer) - 1));

        res.ft.transfer(address(res.market), res.ft.balanceOf(deployer));
        res.xt.transfer(address(res.market), res.xt.balanceOf(deployer));
        vm.stopPrank();
        vm.startPrank(sender);

        uint underlyingAmtIn = res.xt.balanceOf(address(res.market)) / Constants.DECIMAL_BASE / 2;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        vm.expectRevert(abi.encodeWithSelector(ITermMaxMarket.LpOutputAmtIsZero.selector, uint256(underlyingAmtIn)));
        res.market.provideLiquidity(underlyingAmtIn);
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
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.provideLiquidity(underlyingAmtIn);

        vm.stopPrank();
    }

    function testProvideLiquidityWithProviderWhitelist() public {
        vm.prank(deployer);
        res.market.setProviderWhitelist(address(0), false);

        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);

        vm.expectRevert(
            abi.encodeWithSelector(ITermMaxMarket.ProviderNotWhitelisted.selector, sender)
        );
        res.market.provideLiquidity(underlyingAmtIn);

        vm.stopPrank();

        vm.prank(deployer);
        res.market.setProviderWhitelist(sender, true);
        vm.prank(sender);
        res.market.provideLiquidity(underlyingAmtIn);
    }

    function testWithdrawLiquidity() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);

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
        vm.expectEmit();
        emit ITermMaxMarket.WithdrawLiquidity(
            sender,
            lpFtOutAmt,
            lpXtOutAmt,
            uint128(expectFtOutAmt),
            uint128(expectXtOutAmt),
            int64(expectedState.apr)
        );
        (uint128 ftOutAmt, uint128 xtOutAmt) = res.market.withdrawLiquidity(
            lpFtOutAmt,
            lpXtOutAmt
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
        res.lpFt.approve(address(res.market), lpFtBlance);

        vm.expectRevert(
            abi.encodeWithSelector(
                TermMaxCurve.LiquidityIsZeroAfterTransaction.selector
            )
        );
        res.market.withdrawLiquidity(uint128(lpFtBlance), 0);

        uint lpXtBlance = res.lpXt.balanceOf(deployer);
        res.lpXt.approve(address(res.market), lpXtBlance);

        vm.expectRevert(
            abi.encodeWithSelector(
                TermMaxCurve.LiquidityIsZeroAfterTransaction.selector
            )
        );
        res.market.withdrawLiquidity(0, uint128(lpXtBlance));

        vm.stopPrank();
    }

    function testWithdrawLiquidityWhenFtIsMore() public {
        vm.startPrank(sender);

        uint128 underlyingAmtIn = 100e8;
        res.underlying.mint(sender, underlyingAmtIn);
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);

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
        vm.expectEmit();
        emit ITermMaxMarket.WithdrawLiquidity(
            sender,
            lpFtOutAmt,
            lpXtOutAmt / 2,
            uint128(expectFtOutAmt),
            uint128(expectXtOutAmt),
            int64(expectedState.apr)
        );
        (uint128 ftOutAmt, uint128 xtOutAmt) = res.market.withdrawLiquidity(
            lpFtOutAmt,
            lpXtOutAmt / 2
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
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);

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
        vm.expectEmit();
        emit ITermMaxMarket.WithdrawLiquidity(
            sender,
            lpFtOutAmt / 2,
            lpXtOutAmt,
            uint128(expectFtOutAmt),
            uint128(expectXtOutAmt),
            int64(expectedState.apr)
        );
        (uint128 ftOutAmt, uint128 xtOutAmt) = res.market.withdrawLiquidity(
            lpFtOutAmt / 2,
            lpXtOutAmt
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
        res.underlying.approve(address(res.market), underlyingAmtIn);
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            underlyingAmtIn
        );

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);
        vm.warp(res.market.config().maturity - 1);
        res.market.withdrawLiquidity(lpFtOutAmt, lpXtOutAmt);

        vm.stopPrank();
    }

    function testWithdrawLiquidityAfterMaturity() public {
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
            abi.encodeWithSelector(ITermMaxMarket.MarketIsNotOpen.selector)
        );
        res.market.withdrawLiquidity(lpFtOutAmt, lpXtOutAmt);

        vm.stopPrank();
    }
}
