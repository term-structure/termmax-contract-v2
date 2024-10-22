// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TermMaxStorage} from "../storage/TermMaxStorage.sol";

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

    uint32 public constant DECIMAL_BASE = 1e8;
    uint64 public constant DECIMAL_BASE_SQRT = 1e16;
    uint16 public constant DAYS_IN_YEAR = 365;
    uint32 public constant SECONDS_IN_DAY = 86400;
    uint32 public constant SECONDS_IN_MOUNTH = 2592000;

    /**
     * function provide_liquidity(
            uint128 amount,
            uint256 token_supply,
            uint256 total_supply
        ) public pure returns (uint256) {
            if (token_supply == 0) {
                return amount;
            } else {
                return (uint256(amount) * total_supply) / token_supply;
            }
        }
    */
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

    /*
    function calc_x_plus_alpha(
        uint32 gamma_numerator_,
        uint128 x
    ) public pure returns (uint128) {
        return
            uint128(
                (uint256(x) * uint256(gamma_numerator_)) /
                    YieldAmplifierMarketLib.GammaDenominator
            );
    }
    */
    function calcFtPlusAlpha(
        uint32 gamma,
        uint256 ftReserve
    ) public pure returns (uint256) {
        return ftReserve.mulDiv(gamma, DECIMAL_BASE);
    }

    /**
     * function calc_y_plus_beta(
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        int64 apy_numerator_,
        uint128 x
    ) public pure returns (uint128) {
        uint256 apy_numerator_offset_64 = uint256(
            int256(apy_numerator_) +
                int256(YieldAmplifierMarketLib.APYNumeratorOffset)
        );
        uint256 x_plus_alpha = uint256(calc_x_plus_alpha(gamma_numerator_, x));
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
    }
     */
    function calcXtPlusBeta(
        uint32 gamma,
        uint32 ltv,
        uint256 daysToMaturity,
        int64 apy,
        uint256 ftReserve
    ) public pure returns (uint256 xtPlusBeta) {
        // xtReserve + beta = (ftReserve + alpha)/(1 + apy*dayToMaturity/365 - lvt)
        uint ftPlusAlpha = calcFtPlusAlpha(gamma, ftReserve);
        // Use DECIMAL_BASE to solve the problem of precision loss
        if (apy >= 0) {
            xtPlusBeta =
                (ftPlusAlpha * DECIMAL_BASE_SQRT) /
                (DECIMAL_BASE +
                    uint(int(apy)).mulDiv(daysToMaturity, DAYS_IN_YEAR) -
                    ltv) /
                DECIMAL_BASE;
        } else {
            xtPlusBeta =
                (ftPlusAlpha * DECIMAL_BASE_SQRT) /
                (DECIMAL_BASE -
                    uint(int(-apy)).mulDiv(daysToMaturity, DAYS_IN_YEAR) -
                    ltv) /
                DECIMAL_BASE;
        }
    }

    /**
     *     
     function calc_apy_numerator(
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 x_plus_alpha,
        uint128 y_plus_beta
    ) public pure returns (int64) {
        uint256 l = YieldAmplifierMarketLib.APYDenominator *
            YieldAmplifierMarketLib.DaysInYear *
            (uint256(x_plus_alpha) *
                YieldAmplifierMarketLib.LTVDenominator +
                uint256(y_plus_beta) *
                uint256(ltv_numerator_));
        uint256 r = uint256(y_plus_beta) *
            YieldAmplifierMarketLib.DaysInYear *
            YieldAmplifierMarketLib.LTVDenominator *
            YieldAmplifierMarketLib.APYDenominator;
        int256 numerator = l > r ? int256(l - r) : -int256(r - l);
        return
            int64(
                numerator /
                    int256(
                        uint256(y_plus_beta) *
                            days_to_maturity *
                            YieldAmplifierMarketLib.LTVDenominator
                    )
            );
    }
    */
    function calcApy(
        uint32 ltv,
        uint256 daysToMaturity,
        uint256 ftPlusAlpha,
        uint256 xtPlusBeta
    ) public pure returns (int64) {
        uint l = DECIMAL_BASE *
            DAYS_IN_YEAR *
            (ftPlusAlpha * DECIMAL_BASE + xtPlusBeta * ltv);
        uint r = xtPlusBeta * DAYS_IN_YEAR * DECIMAL_BASE_SQRT;
        int numerator = l > r ? int(l - r) : -int(r - l);
        int denominator = (xtPlusBeta * daysToMaturity * DECIMAL_BASE)
            .toInt256();
        return (numerator / denominator).toInt64();
    }

    /*function calculate_fee(
        uint32 fee_numerator_,
        uint32 ltv_numerator_,
        uint128 x,
        uint128 y,
        uint128 new_x,
        uint128 new_y
    ) public pure returns (uint128) {
        return
            _calculate_fee(
                fee_numerator_,
                ltv_numerator_,
                (new_x > x) ? (new_x - x) : (x - new_x),
                (new_y > y) ? (new_y - y) : (y - new_y)
            );
    }*/
    function calculateFee(
        uint256 ftReserve,
        uint256 xtReserve,
        uint256 newFtReserve,
        uint256 newXtReserve,
        uint32 feeRatio,
        uint32 ltv
    ) public pure returns (uint256 feeAmt) {
        uint deltaFt = (newFtReserve > ftReserve)
            ? (newFtReserve - ftReserve)
            : (ftReserve - newFtReserve);
        uint deltaXt = (newXtReserve > xtReserve)
            ? (newXtReserve - xtReserve)
            : (xtReserve - newXtReserve);
        feeAmt = _calculateFee(deltaFt, deltaXt, feeRatio, ltv);
    }

    /*function _calculate_fee(
        uint32 fee_numerator_,
        uint32 ltv_numerator_,
        uint128 delta_x,
        uint128 delta_y
    ) public pure returns (uint128) {
        uint256 l = uint256(delta_x) *
            YieldAmplifierMarketLib.LTVDenominator +
            uint256(delta_y) *
            uint256(ltv_numerator_);
        uint256 r = uint256(delta_y) * YieldAmplifierMarketLib.LTVDenominator;
        return
            uint128(
                (((l > r) ? (l - r) : (r - l)) * fee_numerator_) /
                    (YieldAmplifierMarketLib.LTVDenominator *
                        YieldAmplifierMarketLib.FeeDenominator)
            );
    }*/
    function _calculateFee(
        uint256 deltaFt,
        uint256 deltaXt,
        uint32 feeRatio,
        uint32 ltv
    ) public pure returns (uint256 feeAmt) {
        uint l = deltaFt * DECIMAL_BASE + deltaXt * ltv;
        uint r = deltaXt * DECIMAL_BASE;

        if (l > r) {
            feeAmt = (l - r).mulDiv(feeRatio, DECIMAL_BASE_SQRT);
        } else {
            feeAmt = (r - l).mulDiv(feeRatio, DECIMAL_BASE_SQRT);
        }
    }

    /*function calculate_lp_reward(
        uint256 current_time,
        uint256 open_market_time,
        uint256 maturity,
        uint256 lp_token_supply,
        uint128 amount,
        uint256 total_reward
    ) public pure returns (uint256) {
        return
            (total_reward *
                uint256(amount) *
                (current_time - open_market_time)) /
            ((lp_token_supply - total_reward) *
                (2 * maturity - open_market_time - current_time));
    }*/
    function calculateLpReward(
        uint256 currentTime,
        uint256 openMarketTime,
        uint256 maturity,
        uint256 lpSupply,
        uint256 lpAmt,
        uint256 totalReward
    ) public pure returns (uint256 rewards) {
        uint t = (lpSupply - totalReward) *
            (2 * maturity - openMarketTime - currentTime);
        rewards = (totalReward * lpAmt).mulDiv(
            (currentTime - openMarketTime),
            t
        );
    }

    /**
     * function sell_yp(
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 neg_b = uint256(x_plus_alpha) +
            (uint256(y_plus_beta) * uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator +
            uint256(amount);
        uint256 ac = (uint256(y_plus_beta) *
            uint256(amount) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator;
        uint256 delta_y = ((neg_b - sqrt(neg_b * neg_b - 4 * ac)) *
            YieldAmplifierMarketLib.LTVDenominator) /
            uint256(ltv_numerator_) /
            2;
        uint256 delta_x = amount -
            (delta_y * ltv_numerator_) /
            YieldAmplifierMarketLib.LTVDenominator;
        apy_numerator_ = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + delta_x),
            uint128(y_plus_beta - delta_y)
        );
        return (uint128(x + delta_x), uint128(y - delta_y), apy_numerator_);
    }
     */
    function sellFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint negB = ftPlusAlpha +
            xtPlusBeta.mulDiv(config.initialLtv, DECIMAL_BASE) +
            params.amount;
        uint ac = (xtPlusBeta * params.amount).mulDiv(
            config.initialLtv,
            DECIMAL_BASE
        );
        uint deltaXt = ((negB - (negB.sqrt() - 4 * ac).sqrt()) * DECIMAL_BASE) /
            config.initialLtv /
            2;
        uint deltaFt = params.amount -
            deltaXt.mulDiv(config.initialLtv, DECIMAL_BASE);
        newApy = calcApy(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /**
     *function sell_neg_yp(
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) private pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 b = uint256(x_plus_alpha) +
            (uint256(y_plus_beta) * uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator -
            uint256(neg_amount);
        uint256 neg_ac = (uint256(y_plus_beta) *
            uint256(neg_amount) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator;
        uint256 delta_y = ((sqrt(b * b + 4 * neg_ac) - b) *
            YieldAmplifierMarketLib.LTVDenominator) /
            uint256(ltv_numerator_) /
            2;
        uint256 delta_x = uint256(x_plus_alpha) -
            ((uint256(x_plus_alpha) * uint256(y_plus_beta)) /
                (uint256(y_plus_beta) + delta_y));
        apy_numerator_ = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha - delta_x),
            uint128(y_plus_beta + delta_y)
        );
        return (uint128(x - delta_x), uint128(y + delta_y), apy_numerator_);
    }
     */
    function _sellNegFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint b = ftPlusAlpha +
            xtPlusBeta.mulDiv(config.initialLtv, DECIMAL_BASE) -
            params.amount;
        uint negAc = xtPlusBeta.mulDiv(
            params.amount * config.initialLtv,
            DECIMAL_BASE
        );
        uint deltaXt = (((b.sqrt() + 4 * negAc).sqrt() - b) * DECIMAL_BASE) /
            config.initialLtv /
            2;
        uint deltaFt = ftPlusAlpha -
            ftPlusAlpha.mulDiv(xtPlusBeta, xtPlusBeta + deltaXt);
        newApy = calcApy(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    /**
     * function sell_ya(
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 b = uint256(x_plus_alpha) +
            ((uint256(y_plus_beta) - uint256(amount)) *
                uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator;
        uint256 neg_ac = (((uint256(amount) *
            uint256(y_plus_beta) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator;
        uint256 delta_y = ((sqrt(b * b + 4 * neg_ac) - b) *
            YieldAmplifierMarketLib.LTVDenominator) /
            uint256(ltv_numerator_) /
            2;
        uint256 delta_x = ((uint256(amount) - delta_y) *
            uint256(ltv_numerator_)) / YieldAmplifierMarketLib.LTVDenominator;
        apy_numerator_ = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha - delta_x),
            uint128(y_plus_beta + delta_y)
        );
        return (uint128(x - delta_x), uint128(y + delta_y), apy_numerator_);
    }
     */

    function sellXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint deltaXt;
        uint deltaFt;
        {
            // borrow stack space newFtReserve as b
            uint b = ftPlusAlpha +
                (xtPlusBeta - params.amount).mulDiv(
                    config.initialLtv,
                    DECIMAL_BASE
                );
            // borrow stack space newXtReserve as ac
            uint ac = (params.amount * xtPlusBeta).mulDiv(
                config.initialLtv * config.initialLtv,
                DECIMAL_BASE_SQRT
            );
            deltaXt =
                (((b.sqrt() + 4 * ac).sqrt() - b) * DECIMAL_BASE) /
                config.initialLtv /
                2;
            deltaFt = (params.amount - deltaXt).mulDiv(
                config.initialLtv,
                DECIMAL_BASE
            );
        }

        newApy = calcApy(
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
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) private pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
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
        apy_numerator_ = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + delta_x),
            uint128(y_plus_beta - delta_y)
        );
        return (uint128(x + delta_x), uint128(y - delta_y), apy_numerator_);
    }
 */
    function _sellNegXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint negB = ftPlusAlpha +
            (xtPlusBeta + params.amount).mulDiv(
                config.initialLtv,
                DECIMAL_BASE
            );

        uint ac = (params.amount * xtPlusBeta).mulDiv(
            config.initialLtv * config.initialLtv,
            DECIMAL_BASE_SQRT
        );

        uint deltaXt = ((negB - (negB.sqrt() - 4 * ac).sqrt()) * DECIMAL_BASE) /
            config.initialLtv /
            2;
        uint deltaFt = ftPlusAlpha.mulDiv(xtPlusBeta, (xtPlusBeta - deltaXt)) -
            ftPlusAlpha;
        newApy = calcApy(
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
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 delta_y = amount;
        uint256 delta_x = uint256(x_plus_alpha) -
            (uint256(x_plus_alpha) * uint256(y_plus_beta)) /
            (uint256(y_plus_beta) + delta_y);
        int64 new_apy_numerator = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha - delta_x),
            uint128(y_plus_beta + delta_y)
        );
        return (uint128(x - delta_x), uint128(y + delta_y), new_apy_numerator);
    }
     */
    function buyFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint deltaXt = params.amount;
        uint deltaFt = ftPlusAlpha -
            ftPlusAlpha.mulDiv(xtPlusBeta, (xtPlusBeta + deltaXt));
        newApy = calcApy(
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
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 neg_delta_y = neg_amount;
        uint256 neg_delta_x = (uint256(x_plus_alpha) * uint256(y_plus_beta)) /
            (uint256(y_plus_beta) - neg_delta_y) -
            uint256(x_plus_alpha);
        int64 new_apy_numerator = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + neg_delta_x),
            uint128(y_plus_beta - neg_delta_y)
        );
        return (
            uint128(x + neg_delta_x),
            uint128(y - neg_delta_y),
            new_apy_numerator
        );
    }
     */
    function buyNegFt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint negDeltaXt = params.amount;
        uint negDeltaFt = ftPlusAlpha.mulDiv(
            xtPlusBeta,
            (xtPlusBeta - negDeltaXt)
        ) - ftPlusAlpha;
        newApy = calcApy(
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
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 delta_x = (amount * uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator;
        uint256 delta_y = uint256(y_plus_beta) -
            (uint256(y_plus_beta) * uint256(x_plus_alpha)) /
            (uint256(x_plus_alpha) + delta_x);
        int64 new_apy_numerator = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha + delta_x),
            uint128(y_plus_beta - delta_y)
        );
        return (uint128(x + delta_x), uint128(y - delta_y), new_apy_numerator);
    }
     */
    function buyXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint deltaFt = params.amount.mulDiv(config.initialLtv, DECIMAL_BASE);
        uint deltaXt = xtPlusBeta -
            xtPlusBeta.mulDiv(ftPlusAlpha, ftPlusAlpha + deltaFt);
        newApy = calcApy(
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
        uint32 gamma_numerator_,
        uint32 ltv_numerator_,
        uint256 days_to_maturity,
        uint128 neg_amount,
        uint128 x,
        uint128 y,
        int64 apy_numerator_
    ) public pure returns (uint128, uint128, int64) {
        uint128 x_plus_alpha = calc_x_plus_alpha(gamma_numerator_, x);
        uint128 y_plus_beta = calc_y_plus_beta(
            gamma_numerator_,
            ltv_numerator_,
            days_to_maturity,
            apy_numerator_,
            x
        );
        uint256 neg_delta_x = (neg_amount * uint256(ltv_numerator_)) /
            YieldAmplifierMarketLib.LTVDenominator;
        uint256 neg_delta_y = (uint256(y_plus_beta) * uint256(x_plus_alpha)) /
            (uint256(x_plus_alpha) - neg_delta_x) -
            uint256(y_plus_beta);
        int64 new_apy_numerator = calc_apy_numerator(
            ltv_numerator_,
            days_to_maturity,
            uint128(x_plus_alpha - neg_delta_x),
            uint128(y_plus_beta + neg_delta_y)
        );
        return (
            uint128(x - neg_delta_x),
            uint128(y + neg_delta_y),
            new_apy_numerator
        );
    }
     */
    function buyNegXt(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApy)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.gamma, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.gamma,
            config.initialLtv,
            params.daysToMaturity,
            config.apy,
            params.ftReserve
        );
        uint negDeltaFt = params.amount.mulDiv(config.initialLtv, DECIMAL_BASE);
        uint negDeltaXt = xtPlusBeta.mulDiv(
            ftPlusAlpha,
            ftPlusAlpha - negDeltaFt
        ) - xtPlusBeta;
        newApy = calcApy(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - negDeltaFt,
            xtPlusBeta + negDeltaXt
        );

        newFtReserve = params.ftReserve - negDeltaFt;
        newXtReserve = params.xtReserve + negDeltaXt;
    }
}
