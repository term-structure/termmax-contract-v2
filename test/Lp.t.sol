// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {StateChecker} from "./utils/StateChecker.sol";

import {ITermMaxMarket, TermMaxMarket, Constants} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20, ERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import "../contracts/core/factory/TermMaxFactory.sol";

contract FactoryTest is Test {
    address deployer = vm.envAddress("FORK_DEPLOYER_ADDR");

    DeployUtils.Res res;

    TermMaxStorage.MarketConfig marketConfig;

    address sender = vm.randomAddress();

    function setUp() public {
        vm.startPrank(deployer);
        uint32 maxLtv = 0.85e8;
        uint32 liquidationLtv = 0.9e8;

        marketConfig.openTime = uint64(block.timestamp);
        marketConfig.maturity =
            marketConfig.openTime +
            Constants.SECONDS_IN_MOUNTH;
        marketConfig.initialLtv = 0.9e8;
        marketConfig.apr = 0.1e8;
        marketConfig.deliverable = true;
        // DeployUtils deployUtil = new DeployUtils();
        res = DeployUtils.deployMarket(
            deployer,
            marketConfig,
            maxLtv,
            liquidationLtv
        );
        console.log("gNft: ", address(res.gNft));
        vm.stopPrank();
    }

    function testProvideLiquidity() public {
        vm.startPrank(sender);
        uint amount = 10000e8;
        res.underlying.mint(sender, amount * 2);
        res.underlying.approve(address(res.market), amount * 2);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            amount
        );

        state.ftReserve +=
            (amount * marketConfig.initialLtv) /
            Constants.DECIMAL_BASE;
        state.xtReserve += amount;
        state.underlyingReserve += amount;

        StateChecker.checkMarketState(res, state);

        assert(
            lpFtOutAmt ==
                (amount * marketConfig.initialLtv) / Constants.DECIMAL_BASE
        );
        assert(lpXtOutAmt == amount);

        (lpFtOutAmt, lpXtOutAmt) = res.market.provideLiquidity(amount);

        state.ftReserve +=
            (amount * marketConfig.initialLtv) /
            Constants.DECIMAL_BASE;
        state.xtReserve += amount;
        state.underlyingReserve += amount;

        StateChecker.checkMarketState(res, state);

        assert(
            res.lpFt.balanceOf(sender) ==
                ((amount * marketConfig.initialLtv) / Constants.DECIMAL_BASE) *
                    2
        );
        assert(res.lpXt.balanceOf(sender) == amount * 2);

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(sender);

        uint amount = 10000e8;
        res.underlying.mint(sender, amount * 2);
        res.underlying.approve(address(res.market), amount * 2);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            amount
        );

        vm.warp(block.timestamp + 12);

        res.lpFt.approve(address(res.market), lpFtOutAmt);
        res.lpXt.approve(address(res.market), lpXtOutAmt);

        console.log("XtReserve", res.xt.balanceOf(address(res.market)));

        res.market.withdrawLp(lpFtOutAmt, lpXtOutAmt);

        state.underlyingReserve = amount;
        StateChecker.checkMarketState(res, state);

        assert(
            res.ft.balanceOf(sender) ==
                (amount * marketConfig.initialLtv) / Constants.DECIMAL_BASE
        );
        assert(res.xt.balanceOf(sender) == amount);

        vm.stopPrank();
    }

    function testWithdrawLpFt() public {
        vm.startPrank(sender);

        uint amount = 10000e8;
        res.underlying.mint(sender, amount * 2);
        res.underlying.approve(address(res.market), amount * 2);

        StateChecker.MarketState memory state = StateChecker.getMarketState(
            res
        );
        (uint128 lpFtOutAmt, uint128 lpXtOutAmt) = res.market.provideLiquidity(
            amount
        );

        vm.warp(block.timestamp + 12);

        res.lpFt.approve(address(res.market), lpFtOutAmt);

        console.log("XtReserve", res.xt.balanceOf(address(res.market)));

        res.market.withdrawLp(lpFtOutAmt, 0);

        // state.underlyingReserve = amount;
        // StateChecker.checkMarketState(res, state);

        vm.stopPrank();
    }
}
