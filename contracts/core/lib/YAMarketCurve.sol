// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TermMaxStorage} from "../storage/TermMaxStorage.sol";

library YAMarketCurve {
    struct TradeParams {
        uint256 amount;
        uint256 ypReserve;
        uint256 yaReserve;
        uint256 daysToMaturity;
    }

    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint32 public constant DECIMAL_BASE = 1e8;
    uint64 public constant DECIMAL_BASE_SQRT = 1e16;
    uint16 public constant DAYS_IN_YEAR = 365;
    uint32 public constant SECONDS_IN_DAY = 86400;

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
    function calcYpPlusAlpha(
        uint32 gamma,
        uint256 ypReserve
    ) public pure returns (uint256) {
        return ypReserve.mulDiv(gamma, DECIMAL_BASE);
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
    function calcYaPlusBeta(
        uint32 gamma,
        uint32 ltv,
        uint256 daysToMaturity,
        int64 apy,
        uint256 ypReserve
    ) public pure returns (uint256 yaPlusBeta) {
        // yaReserve + beta = (ypReserve + alpha)/(1 + apy*dayToMaturity/365 - lvt)
        uint ypPlusAlpha = calcYpPlusAlpha(gamma, ypReserve);
        // Use DECIMAL_BASE to solve the problem of precision loss
        if (apy >= 0) {
            yaPlusBeta =
                (ypPlusAlpha * DECIMAL_BASE_SQRT) /
                (DECIMAL_BASE +
                    uint(int(apy)).mulDiv(daysToMaturity, DAYS_IN_YEAR) -
                    ltv) /
                DECIMAL_BASE;
        } else {
            yaPlusBeta =
                (ypPlusAlpha * DECIMAL_BASE_SQRT) /
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
        uint256 ypPlusAlpha,
        uint256 yaPlusBeta
    ) public pure returns (int64) {
        uint l = DECIMAL_BASE *
            DAYS_IN_YEAR *
            (ypPlusAlpha * DECIMAL_BASE + yaPlusBeta * ltv);
        uint r = yaPlusBeta * DAYS_IN_YEAR * DECIMAL_BASE_SQRT;
        int numerator = l > r ? int(l - r) : -int(r - l);
        int denominator = (yaPlusBeta * daysToMaturity * DECIMAL_BASE)
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
        uint256 ypReserve,
        uint256 yaReserve,
        uint256 newYpReserve,
        uint256 newYaReserve,
        uint32 feeRatio,
        uint32 ltv
    ) public pure returns (uint256 feeAmt) {
        uint deltaYp = (newYpReserve > ypReserve)
            ? (newYpReserve - ypReserve)
            : (ypReserve - newYpReserve);
        uint deltaYa = (newYaReserve > yaReserve)
            ? (newYaReserve - yaReserve)
            : (yaReserve - newYaReserve);
        feeAmt = _calculateFee(deltaYp, deltaYa, feeRatio, ltv);
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
        uint256 deltaYp,
        uint256 deltaYa,
        uint32 feeRatio,
        uint32 ltv
    ) public pure returns (uint256 feeAmt) {
        uint l = deltaYp * DECIMAL_BASE + deltaYa * ltv;
        uint r = deltaYa * DECIMAL_BASE;

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
    function sellYp(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint negB = ypPlusAlpha +
            yaPlusBeta.mulDiv(config.ltv, DECIMAL_BASE) +
            params.amount;
        uint ac = (yaPlusBeta * params.amount).mulDiv(config.ltv, DECIMAL_BASE);
        uint deltaYa = ((negB - (negB.sqrt() - 4 * ac).sqrt()) * DECIMAL_BASE) /
            config.ltv /
            2;
        uint deltaYp = params.amount - deltaYa.mulDiv(config.ltv, DECIMAL_BASE);
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha + deltaYp,
            yaPlusBeta - deltaYa
        );
        newYpReserve = params.ypReserve + deltaYp;
        newYaReserve = params.yaReserve - deltaYa;
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
    function _sellNegYp(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint b = ypPlusAlpha +
            yaPlusBeta.mulDiv(config.ltv, DECIMAL_BASE) -
            params.amount;
        uint negAc = yaPlusBeta.mulDiv(
            params.amount * config.ltv,
            DECIMAL_BASE
        );
        uint deltaYa = (((b.sqrt() + 4 * negAc).sqrt() - b) * DECIMAL_BASE) /
            config.ltv /
            2;
        uint deltaYp = ypPlusAlpha -
            ypPlusAlpha.mulDiv(yaPlusBeta, yaPlusBeta + deltaYa);
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha - deltaYp,
            yaPlusBeta + deltaYa
        );
        newYpReserve = params.ypReserve - deltaYp;
        newYaReserve = params.yaReserve + deltaYa;
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

    function sellYa(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint deltaYa;
        uint deltaYp;
        {
            // borrow stack space newYpReserve as b
            uint b = ypPlusAlpha +
                (yaPlusBeta - params.amount).mulDiv(config.ltv, DECIMAL_BASE);
            // borrow stack space newYaReserve as ac
            uint ac = (params.amount * yaPlusBeta).mulDiv(
                config.ltv * config.ltv,
                DECIMAL_BASE_SQRT
            );
            deltaYa =
                (((b.sqrt() + 4 * ac).sqrt() - b) * DECIMAL_BASE) /
                config.ltv /
                2;
            deltaYp = (params.amount - deltaYa).mulDiv(
                config.ltv,
                DECIMAL_BASE
            );
        }

        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha - deltaYp,
            yaPlusBeta + deltaYa
        );
        newYpReserve = params.ypReserve - deltaYp;
        newYaReserve = params.yaReserve + deltaYa;
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
    function _sellNegYa(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint negB = ypPlusAlpha +
            (yaPlusBeta + params.amount).mulDiv(config.ltv, DECIMAL_BASE);

        uint ac = (params.amount * yaPlusBeta).mulDiv(
            config.ltv * config.ltv,
            DECIMAL_BASE_SQRT
        );

        uint deltaYa = ((negB - (negB.sqrt() - 4 * ac).sqrt()) * DECIMAL_BASE) /
            config.ltv /
            2;
        uint deltaYp = ypPlusAlpha.mulDiv(yaPlusBeta, (yaPlusBeta - deltaYa)) -
            ypPlusAlpha;
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha + deltaYp,
            yaPlusBeta - deltaYa
        );
        newYpReserve = params.ypReserve + deltaYp;
        newYaReserve = params.yaReserve - deltaYa;
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
    function buyYp(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint deltaYa = params.amount;
        uint deltaYp = ypPlusAlpha -
            ypPlusAlpha.mulDiv(yaPlusBeta, (yaPlusBeta + deltaYa));
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha - deltaYp,
            yaPlusBeta + deltaYa
        );
        newYpReserve = params.ypReserve - deltaYp;
        newYaReserve = params.yaReserve + deltaYa;
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
    function buyNegYp(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint negDeltaYa = params.amount;
        uint negDeltaYp = ypPlusAlpha.mulDiv(
            yaPlusBeta,
            (yaPlusBeta - negDeltaYa)
        ) - ypPlusAlpha;
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha + negDeltaYp,
            yaPlusBeta - negDeltaYa
        );
        newYpReserve = params.ypReserve + negDeltaYp;
        newYaReserve = params.yaReserve - negDeltaYa;
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
    function buyYa(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint deltaYp = params.amount.mulDiv(config.ltv, DECIMAL_BASE);
        uint deltaYa = yaPlusBeta -
            yaPlusBeta.mulDiv(ypPlusAlpha, ypPlusAlpha + deltaYp);
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha + deltaYp,
            yaPlusBeta - deltaYa
        );
        newYpReserve = params.ypReserve + deltaYp;
        newYaReserve = params.yaReserve - deltaYa;
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
    function buyNegYa(
        TradeParams memory params,
        TermMaxStorage.MarketConfig memory config
    )
        public
        pure
        returns (uint256 newYpReserve, uint256 newYaReserve, int64 newApy)
    {
        uint ypPlusAlpha = calcYpPlusAlpha(config.gamma, params.ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            config.gamma,
            config.ltv,
            params.daysToMaturity,
            config.apy,
            params.ypReserve
        );
        uint negDeltaYp = params.amount.mulDiv(config.ltv, DECIMAL_BASE);
        uint negDeltaYa = yaPlusBeta.mulDiv(
            ypPlusAlpha,
            ypPlusAlpha - negDeltaYp
        ) - yaPlusBeta;
        newApy = calcApy(
            config.ltv,
            params.daysToMaturity,
            ypPlusAlpha - negDeltaYp,
            yaPlusBeta + negDeltaYa
        );

        newYpReserve = params.ypReserve - negDeltaYp;
        newYaReserve = params.yaReserve + negDeltaYa;
    }
}
