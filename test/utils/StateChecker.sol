// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {DeployUtils} from "./DeployUtils.sol";
import {Constants} from "../../contracts/core/lib/Constants.sol";
import "../../contracts/core/storage/TermMaxStorage.sol";

library StateChecker {
    struct TokenPairState {
        uint collateralReserve;
        uint underlyingReserve;
    }

    struct MarketState {
        uint ftReserve;
        uint xtReserve;
    }

    function checkTokenPairState(
        DeployUtils.Res memory res,
        TokenPairState memory expect
    ) internal view {
        require(
            res.collateral.balanceOf(address(res.gt)) == expect.collateralReserve,
            "collateralReserve unexpect"
        );
        require(
            res.underlying.balanceOf(address(res.tokenPair)) == expect.underlyingReserve,
            "underlyingReserve unexpect"
        );
    }

    function getTokenPairState(
        DeployUtils.Res memory res
    ) internal view returns (TokenPairState memory state) {
        state.collateralReserve = res.collateral.balanceOf(address(res.gt));
        state.underlyingReserve = res.underlying.balanceOf(address(res.tokenPair));
    }

    function checkMarketState(
        DeployUtils.Res memory res,
        MarketState memory expect
    ) internal view {
        address market = address(res.market);
        require(
            res.ft.balanceOf(market) == expect.ftReserve,
            "ftReserve unexpect"
        );
        require(
            res.xt.balanceOf(market) == expect.xtReserve,
            "xtReserve unexpect"
        );
    }

    function getMarketState(
        DeployUtils.Res memory res
    ) internal view returns (MarketState memory state) {
        address market = address(res.market);
        state.ftReserve = res.ft.balanceOf(market);
        state.xtReserve = res.xt.balanceOf(market);
    }

    function getUserBalances(
        DeployUtils.Res memory res,
        address user
    ) internal view returns (uint[6] memory balances) {
        balances[0] = res.ft.balanceOf(user);
        balances[1] = res.xt.balanceOf(user);
    }
}
