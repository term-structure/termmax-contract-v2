// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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
        assert(res.market.config().apr == expect.apr);
        assert(res.ft.balanceOf(market) == expect.ftReserve);
        assert(res.xt.balanceOf(market) == expect.xtReserve);
        assert(res.lpFt.balanceOf(market) == expect.lpFtReserve);
        assert(res.lpXt.balanceOf(market) == expect.lpXtReserve);
        assert(res.underlying.balanceOf(market) == expect.underlyingReserve);
        assert(
            res.collateral.balanceOf(address(res.gt)) ==
                expect.collateralReserve
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
