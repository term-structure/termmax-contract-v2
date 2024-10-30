// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TermMaxStorage} from "../storage/TermMaxStorage.sol";
import {Constants} from "./Constants.sol";

library TermMaxCurve {
    struct TradeParams {
        uint256 amount;
        uint256 ftReserve;
        uint256 xtReserve;
        uint256 daysToMaturity;
    }

    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    function _calculateLpOut(
        uint256 tokenIn,
        uint256 tokenReserve,
        uint256 lpTotalSupply
    ) internal pure returns (uint256 lpOutAmt) {
        if (lpTotalSupply == 0) {
            lpOutAmt = tokenIn;
        } else {
            // lpOutAmt = tokenIn/(tokenReserve/lpTotalSupply) = tokenIn*lpTotalSupply/tokenReserve
            lpOutAmt = tokenIn.mulDiv(lpTotalSupply, tokenReserve);
        }
    }

    function _calcFtPlusAlpha(
        uint32 lsf,
        uint256 ftReserve
    ) internal pure returns (uint256) {
        return ftReserve.mulDiv(lsf, Constants.DECIMAL_BASE);
    }

    /**
     *     function calc_y_plus_beta(
        uint32 lsf _numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        int64 apy_numerator_,
        uint128 x
    ) public pure returns (uint128) {
        uint256 apy_numerator_offset_64 = uint256(
            int256(apy_numerator_) +
                int256(YieldAmplifierMarketLib.APYNumeratorOffset)
        );
        uint256 x_plus_alpha = uint256(calc_x_plus_alpha(lsf _numerator_, x));
        return
            uint128(
                (x_plus_alpha *
                    YieldAmplifierMarketLib.APYDenominator *
                    YieldAmplifierMarketLib.LTVDenominator *
                    YieldAmplifierMarketLib.DaysInYear) /
                    (YieldAmplifierMarketLib.APYDenominator *
                        YieldAmplifierMarketLib.LTVDenominator *
                        YieldAmplifierMarketLib.DaysInYear +
                        apy_numerator_offset_64 *
                        days_to_maturity *
                        YieldAmplifierMarketLib.LTVDenominator -
                        YieldAmplifierMarketLib.APYNumeratorOffset *
                        days_to_maturity *
                        YieldAmplifierMarketLib.LTVDenominator -
                        YieldAmplifierMarketLib.APYDenominator *
                        YieldAmplifierMarketLib.DaysInYear *
                        uint256(ltv_numerator_))
            );

        x_plus_alpha*YieldAmplifierMarketLib.DaysInYear/(apr*days_to_maturity)
    }
     */
    function _calcXtPlusBeta(
        uint32 lsf,
        uint32 ltv,
        uint256 daysToMaturity,
        int64 apr,
        uint256 ftReserve
    ) internal pure returns (uint256 xtPlusBeta) {
        // xtReserve + beta = (ftReserve + alpha)/(1 + apr*dayToMaturity/365 - lvt)
        uint ftPlusAlpha = _calcFtPlusAlpha(lsf, ftReserve);
        // Use Constants.DECIMAL_BASE to solve the problem of precision loss
        if (apr >= 0) {
            xtPlusBeta =
                (ftPlusAlpha *
                    Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR) /
                (Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR +
                    uint(int(apr)) *
                    daysToMaturity -
                    ltv *
                    Constants.DAYS_IN_YEAR);
        } else {
            xtPlusBeta =
                (ftPlusAlpha *
                    Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR) /
                (Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR -
                    uint(int(-apr)) *
                    daysToMaturity -
                    ltv *
                    Constants.DAYS_IN_YEAR);
        }
    }

    function _calcApr(
        uint32 ltv,
        uint256 daysToMaturity,
        uint256 ftPlusAlpha,
        uint256 xtPlusBeta
    ) internal pure returns (int64) {
        uint l = Constants.DECIMAL_BASE *
            Constants.DAYS_IN_YEAR *
            (ftPlusAlpha * Constants.DECIMAL_BASE + xtPlusBeta * ltv);
        uint r = xtPlusBeta *
            Constants.DAYS_IN_YEAR *
            Constants.DECIMAL_BASE_SQ;
        int numerator = l > r ? int(l - r) : -int(r - l);
        int denominator = (xtPlusBeta * daysToMaturity * Constants.DECIMAL_BASE)
            .toInt256();
        return (numerator / denominator).toInt64();
    }

    function _calculateFee(
        uint256 ftReserve,
        uint256 xtReserve,
        uint256 newFtReserve,
        uint256 newXtReserve,
        uint32 feeRatio,
        uint32 ltv
    ) internal pure returns (uint256 feeAmt) {
        uint deltaFt = (newFtReserve > ftReserve)
            ? (newFtReserve - ftReserve)
            : (ftReserve - newFtReserve);
        uint deltaXt = (newXtReserve > xtReserve)
            ? (newXtReserve - xtReserve)
            : (xtReserve - newXtReserve);
        feeAmt = _calculateFeeInternal(deltaFt, deltaXt, feeRatio, ltv);
    }

    function _calculateFeeInternal(
        uint256 deltaFt,
        uint256 deltaXt,
        uint32 feeRatio,
        uint32 ltv
    ) internal pure returns (uint256 feeAmt) {
        uint l = deltaFt * Constants.DECIMAL_BASE + deltaXt * ltv;
        uint r = deltaXt * Constants.DECIMAL_BASE;

        if (l > r) {
            feeAmt = (l - r).mulDiv(feeRatio, Constants.DECIMAL_BASE_SQ);
        } else {
            feeAmt = (r - l).mulDiv(feeRatio, Constants.DECIMAL_BASE_SQ);
        }
    }

    function _calculateLpReward(
        uint256 currentTime,
        uint256 openMarketTime,
        uint256 maturity,
        uint256 lpSupply,
        uint256 lpAmt,
        uint256 totalReward
    ) internal pure returns (uint256 reward) {
        uint t = (lpSupply - totalReward) *
            (2 * maturity - openMarketTime - currentTime);
        reward = (totalReward * lpAmt).mulDiv(
            (currentTime - openMarketTime),
            t
        );
    }

    function _sellFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint negB = ftPlusAlpha +
            xtPlusBeta.mulDiv(config.initialLtv, Constants.DECIMAL_BASE) +
            params.amount;
        uint ac = (xtPlusBeta * params.amount).mulDiv(
            config.initialLtv,
            Constants.DECIMAL_BASE
        );
        uint deltaXt = ((negB - (negB.sqrt() - 4 * ac).sqrt()) *
            Constants.DECIMAL_BASE) /
            config.initialLtv /
            2;
        uint deltaFt = params.amount -
            deltaXt.mulDiv(config.initialLtv, Constants.DECIMAL_BASE);
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    function _sellNegFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint b = ftPlusAlpha +
            xtPlusBeta.mulDiv(config.initialLtv, Constants.DECIMAL_BASE) -
            params.amount;
        uint negAc = xtPlusBeta.mulDiv(
            params.amount * config.initialLtv,
            Constants.DECIMAL_BASE
        );
        uint deltaXt = (((b.sqrt() + 4 * negAc).sqrt() - b) *
            Constants.DECIMAL_BASE) /
            config.initialLtv /
            2;
        uint deltaFt = ftPlusAlpha -
            ftPlusAlpha.mulDiv(xtPlusBeta, xtPlusBeta + deltaXt);
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    function _sellXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaXt;
        uint deltaFt;
        {
            // borrow stack space newFtReserve as b
            uint b = ftPlusAlpha +
                (xtPlusBeta - params.amount).mulDiv(
                    config.initialLtv,
                    Constants.DECIMAL_BASE
                );
            // borrow stack space newXtReserve as ac
            uint ac = (params.amount * xtPlusBeta).mulDiv(
                config.initialLtv * config.initialLtv,
                Constants.DECIMAL_BASE_SQ
            );
            deltaXt =
                (((b.sqrt() + 4 * ac).sqrt() - b) * Constants.DECIMAL_BASE) /
                config.initialLtv /
                2;
            deltaFt = (params.amount - deltaXt).mulDiv(
                config.initialLtv,
                Constants.DECIMAL_BASE
            );
        }

        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    /**
 * function sell_neg_ya(
        uint32 lsf _numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apr_numerator_
    ) private pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(lsf _numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            lsf _numerator_,
            ltv_numerator_,
            days_to_maturity,
            apr_numerator_,
            x
        );
        uint256 neg_b = uint256(x_plus_alpha) +
            ((uint256(y_plus_beta) + uint256(neg_amount)) *
                uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator;
        uint256 ac = (((uint256(neg_amount) *
            uint256(y_plus_beta) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator;
        uint256 delta_y = ((neg_b - sqrt(neg_b * neg_b - 4 * ac)) *
            YieldAmplifierMarketLib.LTVDenominator) /
            uint256(ltv_numerator_) /
            2;
        uint256 delta_x = ((uint256(x_plus_alpha) * uint256(y_plus_beta)) /
            (uint256(y_plus_beta) - delta_y)) - uint256(x_plus_alpha);
        apr_numerator_ = calc_apr_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + delta_x),
            uint128(y_plus_beta - delta_y)
        );
        return (uint128(x + delta_x), uint128(y - delta_y), apr_numerator_);
    }
 */
    function _sellNegXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint negB = ftPlusAlpha +
            (xtPlusBeta + params.amount).mulDiv(
                config.initialLtv,
                Constants.DECIMAL_BASE
            );

        uint ac = (params.amount * xtPlusBeta).mulDiv(
            config.initialLtv * config.initialLtv,
            Constants.DECIMAL_BASE_SQ
        );

        uint deltaXt = ((negB - (negB.sqrt() - 4 * ac).sqrt()) *
            Constants.DECIMAL_BASE) /
            config.initialLtv /
            2;
        uint deltaFt = ftPlusAlpha.mulDiv(xtPlusBeta, (xtPlusBeta - deltaXt)) -
            ftPlusAlpha;
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /**
     * function buy_yp(
        uint32 lsf _numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 amount,
        uint128 x,
        uint128 y,
        int64 apr_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(lsf _numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            lsf _numerator_,
            ltv_numerator_,
            days_to_maturity,
            apr_numerator_,
            x
        );
        uint256 delta_y = amount;
        uint256 delta_x = uint256(x_plus_alpha) -
            (uint256(x_plus_alpha) * uint256(y_plus_beta)) /
            (uint256(y_plus_beta) + delta_y);
        int64 new_apr_numerator = calc_apr_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha - delta_x),
            uint128(y_plus_beta + delta_y)
        );
        return (uint128(x - delta_x), uint128(y + delta_y), new_apr_numerator);
    }
     */
    function _buyFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaXt = params.amount;
        uint deltaFt = ftPlusAlpha -
            ftPlusAlpha.mulDiv(xtPlusBeta, (xtPlusBeta + deltaXt));
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    /**
     *function buy_neg_yp(
        uint32 lsf _numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apr_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(lsf _numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            lsf _numerator_,
            ltv_numerator_,
            days_to_maturity,
            apr_numerator_,
            x
        );
        uint256 neg_delta_y = neg_amount;
        uint256 neg_delta_x = (uint256(x_plus_alpha) * uint256(y_plus_beta)) /
            (uint256(y_plus_beta) - neg_delta_y) -
            uint256(x_plus_alpha);
        int64 new_apr_numerator = calc_apr_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + neg_delta_x),
            uint128(y_plus_beta - neg_delta_y)
        );
        return (
            uint128(x + neg_delta_x),
            uint128(y - neg_delta_y),
            new_apr_numerator
        );
    }
     */
    function _buyNegFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint negDeltaXt = params.amount;
        uint negDeltaFt = ftPlusAlpha.mulDiv(
            xtPlusBeta,
            (xtPlusBeta - negDeltaXt)
        ) - ftPlusAlpha;
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + negDeltaFt,
            xtPlusBeta - negDeltaXt
        );
        newFtReserve = params.ftReserve + negDeltaFt;
        newXtReserve = params.xtReserve - negDeltaXt;
    }

    /**
     *function buy_ya(
        uint32 lsf _numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 amount,
        uint128 x,
        uint128 y,
        int64 apr_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(lsf _numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            lsf _numerator_,
            ltv_numerator_,
            days_to_maturity,
            apr_numerator_,
            x
        );
        uint256 delta_x = (amount * uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator;
        uint256 delta_y = uint256(y_plus_beta) -
            (uint256(y_plus_beta) * uint256(x_plus_alpha)) /
            (uint256(x_plus_alpha) + delta_x);
        int64 new_apr_numerator = calc_apr_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + delta_x),
            uint128(y_plus_beta - delta_y)
        );
        return (uint128(x + delta_x), uint128(y - delta_y), new_apr_numerator);
    }
     */
    function _buyXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaFt = params.amount.mulDiv(
            config.initialLtv,
            Constants.DECIMAL_BASE
        );
        uint deltaXt = xtPlusBeta -
            xtPlusBeta.mulDiv(ftPlusAlpha, ftPlusAlpha + deltaFt);
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /**
     *function buy_neg_ya(
        uint32 lsf _numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apr_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(lsf _numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            lsf _numerator_,
            ltv_numerator_,
            days_to_maturity,
            apr_numerator_,
            x
        );
        uint256 neg_delta_x = (neg_amount * uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator;
        uint256 neg_delta_y = (uint256(y_plus_beta) * uint256(x_plus_alpha)) /
            (uint256(x_plus_alpha) - neg_delta_x) -
            uint256(y_plus_beta);
        int64 new_apr_numerator = calc_apr_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha - neg_delta_x),
            uint128(y_plus_beta + neg_delta_y)
        );
        return (
            uint128(x - neg_delta_x),
            uint128(y + neg_delta_y),
            new_apr_numerator
        );
    }
     */
    function _buyNegXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = _calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = _calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint negDeltaFt = params.amount.mulDiv(
            config.initialLtv,
            Constants.DECIMAL_BASE
        );
        uint negDeltaXt = xtPlusBeta.mulDiv(
            ftPlusAlpha,
            ftPlusAlpha - negDeltaFt
        ) - xtPlusBeta;
        newApr = _calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - negDeltaFt,
            xtPlusBeta + negDeltaXt
        );

        newFtReserve = params.ftReserve - negDeltaFt;
        newXtReserve = params.xtReserve + negDeltaXt;
    }
}
