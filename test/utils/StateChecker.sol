// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {DeployUtils} from "./DeployUtils.sol";
import {Constants} from "../../contracts/core/lib/Constants.sol";
import "../../contracts/core/storage/TermMaxStorage.sol";

library StateChecker {
    struct MarketState {
        int apr;
        uint ftReserve;
        uint xtReserve;
        uint lpFtReserve;
        uint lpXtReserve;
        uint underlyingReserve;
        uint collateralReserve;
        uint lpFtTotalSupply;
        uint lpXtTotalSupply;
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
        require(
            res.lpFt.totalSupply() == expect.lpFtTotalSupply,
            "lpFtTotalSupply unexpect"
        );
        require(
            res.lpXt.totalSupply() == expect.lpXtTotalSupply,
            "lpXtTotalSupply unexpect"
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
        state.lpFtTotalSupply = res.lpFt.totalSupply();
        state.lpXtTotalSupply = res.lpXt.totalSupply();
    }

    function getUserBalances(
        DeployUtils.Res memory res,
        address user
    ) internal view returns (uint[6] memory balances) {
        balances[0] = res.ft.balanceOf(user);
        balances[1] = res.xt.balanceOf(user);
        balances[2] = res.lpFt.balanceOf(user);
        balances[3] = res.lpXt.balanceOf(user);
        balances[4] = res.collateral.balanceOf(user);
        balances[5] = res.underlying.balanceOf(user);
    }

    function getRedeemPoints(
        DeployUtils.Res memory res,
        MarketConfig memory config,
        uint[4] memory amounts
    )
        internal
        view
        returns (
            uint128 propotion,
            uint128 underlyingAmt,
            uint128 feeAmt,
            bytes memory deliveryData
        )
    {
        uint ftTotal = res.ft.totalSupply() - res.ft.balanceOf(address(res.gt));
        uint xtTotal = res.xt.totalSupply();

        // k = (1 - initalLtv) * DECIMAL_BASE
        uint k = Constants.DECIMAL_BASE - config.initialLtv;

        uint ftAmt;
        uint xtAmt;
        //ft
        if (amounts[0] > 0) {
            ftAmt += amounts[0];
        }

        //xt
        if (amounts[1] > 0) {
            xtAmt += amounts[1];
        }

        if (amounts[2] > 0) {
            uint lpftTotal = res.lpFt.totalSupply() -
                res.lpFt.balanceOf(address(res.market));
            //lpft
            ftAmt +=
                (amounts[2] * res.ft.balanceOf(address(res.market))) /
                lpftTotal;
        }

        if (amounts[3] > 0) {
            //lpxt
            xtAmt +=
                (amounts[3] * res.xt.balanceOf(address(res.market))) /
                (res.lpXt.totalSupply() -
                    res.lpXt.balanceOf(address(res.market)));
        }
        uint xtAsUnderlying = (xtAmt * k) / Constants.DECIMAL_BASE;
        uint allXtAsUnderlying = (xtTotal * k) / Constants.DECIMAL_BASE;
        propotion = uint128((ftAmt * Constants.DECIMAL_BASE_SQ) / ftTotal);

        uint underlyingReserve = res.underlying.balanceOf(address(res.market));
        underlyingAmt = uint128(
            xtAsUnderlying +
                (propotion * (underlyingReserve - allXtAsUnderlying)) /
                Constants.DECIMAL_BASE_SQ
        );
        feeAmt = uint128(
            (underlyingAmt * config.redeemFeeRatio) / Constants.DECIMAL_BASE
        );
        underlyingAmt -= feeAmt;
        deliveryData = abi.encode(
            (propotion * res.collateral.balanceOf(address(res.gt))) /
                Constants.DECIMAL_BASE_SQ
        );
    }
}
