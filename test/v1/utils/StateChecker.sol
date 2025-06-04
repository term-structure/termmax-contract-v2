// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {DeployUtils} from "./DeployUtils.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

library StateChecker {
    struct MarketState {
        uint256 collateralReserve;
        uint256 debtReserve;
    }

    struct OrderState {
        uint256 ftReserve;
        uint256 xtReserve;
    }

    function checkMarketState(DeployUtils.Res memory res, MarketState memory expect) internal view {
        require(res.collateral.balanceOf(address(res.gt)) == expect.collateralReserve, "collateralReserve unexpect");
        require(res.debt.balanceOf(address(res.market)) == expect.debtReserve, "debtReserve unexpect");
    }

    function getMarketState(DeployUtils.Res memory res) internal view returns (MarketState memory state) {
        state.collateralReserve = res.collateral.balanceOf(address(res.gt));
        state.debtReserve = res.debt.balanceOf(address(res.market));
    }

    function checkOrderState(DeployUtils.Res memory res, OrderState memory expect) internal view {
        address order = address(res.order);
        require(res.ft.balanceOf(order) == expect.ftReserve, "ftReserve unexpect");
        require(res.xt.balanceOf(order) == expect.xtReserve, "xtReserve unexpect");
    }

    function getOrderState(DeployUtils.Res memory res) internal view returns (OrderState memory state) {
        address order = address(res.order);
        state.ftReserve = res.ft.balanceOf(order);
        state.xtReserve = res.xt.balanceOf(order);
    }

    function getUserBalances(DeployUtils.Res memory res, address user)
        internal
        view
        returns (uint256[6] memory balances)
    {
        balances[0] = res.ft.balanceOf(user);
        balances[1] = res.xt.balanceOf(user);
        balances[2] = res.debt.balanceOf(user);
        balances[3] = res.collateral.balanceOf(user);
    }
}
