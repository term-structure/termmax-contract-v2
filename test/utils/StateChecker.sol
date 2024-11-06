// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {DeployUtils} from "./DeployUtils.sol";

library StateChecker {
    struct MarketState {
        int apr;
        uint ftReserve;
        uint xtReserve;
        uint lpFtReserve;
        uint lpXtReserve;
        uint underlyingReserve;
        uint collateralReserve;
    }

    function checkMarketState(
        DeployUtils.Res memory res,
        MarketState memory expect
    ) internal view {
        address market = address(res.market);
        require(res.market.config().apr == expect.apr, "apr unexpect");
        require(
            res.ft.balanceOf(market) == expect.ftReserve,
            "ftReserve unexpect"
        );
        require(
            res.xt.balanceOf(market) == expect.xtReserve,
            "xtReserve unexpect"
        );
        require(
            res.lpFt.balanceOf(market) == expect.lpFtReserve,
            "lpFtReserve unexpect"
        );
        require(
            res.lpXt.balanceOf(market) == expect.lpXtReserve,
            "lpXtReserve unexpect"
        );
        require(
            res.underlying.balanceOf(market) == expect.underlyingReserve,
            "underlyingReserve unexpect"
        );

        require(
            res.collateral.balanceOf(address(res.gt)) ==
                expect.collateralReserve,
            "collateralReserve unexpect"
        );
    }

    function getMarketState(
        DeployUtils.Res memory res
    ) internal view returns (MarketState memory state) {
        address market = address(res.market);
        state.apr = res.market.config().apr;
        state.ftReserve = res.ft.balanceOf(market);
        state.xtReserve = res.xt.balanceOf(market);
        state.lpFtReserve = res.lpFt.balanceOf(market);
        state.lpXtReserve = res.lpXt.balanceOf(market);
        state.underlyingReserve = res.underlying.balanceOf(market);
        state.collateralReserve = res.collateral.balanceOf(address(res.gt));
    }
}
