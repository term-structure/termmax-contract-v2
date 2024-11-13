// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Constants} from "./Constants.sol";
import {MathLib, SafeCast} from "./MathLib.sol";
import "../storage/TermMaxStorage.sol";

/**
 * @title The TermMax curve library
 * @author Term Structure Labs
 */
library TermMaxCurve {
    using SafeCast for uint256;
    using SafeCast for int256;
    using MathLib for *;

    /// @notice Error for transaction lead to liquidity depletion
    error LiquidityIsZeroAfterTransaction();

    int constant INT_64_MAX = type(int64).max;
    int constant INT_64_MIN = type(int64).min;

    /// @notice Calculate how many lp tokens should be minted to the liquidity provider
    /// @param tokenIn The amount of tokens provided
    /// @param tokenReserve The token's balance of the market
    /// @param lpTotalSupply The total supply of this lp token
    /// @return lpOutAmt The amount of lp tokens to be minted to the liquidity provider
    function calculateLpOut(
        uint256 tokenIn,
        uint256 tokenReserve,
        uint256 lpTotalSupply
    ) internal pure returns (uint256 lpOutAmt) {
        if (lpTotalSupply == 0) {
            lpOutAmt = tokenIn;
        } else {
            // lpOutAmt/lpTotalSupply = tokenIn/tokenReserve
            lpOutAmt = (tokenIn * lpTotalSupply) / tokenReserve;
        }
    }

    /// @notice Calculte the FT token reserve plus alpha
    /// @param lsf The liquidity scaling factor
    /// @param ftReserve The FT token reserve of the market
    /// @return ftPlusAlpha The FT token reserve plus alpha
    function calcFtPlusAlpha(
        uint32 lsf,
        uint256 ftReserve
    ) internal pure returns (uint256 ftPlusAlpha) {
        ftPlusAlpha = (ftReserve * Constants.DECIMAL_BASE) / lsf;
        if (ftPlusAlpha == 0) {
            revert LiquidityIsZeroAfterTransaction();
        }
    }

    /// @notice Calculte the XT token reserve plus beta
    /// @param lsf The liquidity scaling factor
    /// @param ltv The initial ltv of the market
    /// @param daysToMaturity The days until maturity
    /// @param apr The annual interest rate of the market
    /// @param ftReserve The FT token reserve of the market
    /// @return xtPlusBeta The XT token reserve plus beta
    function calcXtPlusBeta(
        uint32 lsf,
        uint32 ltv,
        uint256 daysToMaturity,
        int64 apr,
        uint256 ftReserve
    ) internal pure returns (uint256 xtPlusBeta) {
        // xtReserve + beta = (ftReserve + alpha)/(1 + apr*dayToMaturity/365 - lvt)
        uint ftPlusAlpha = calcFtPlusAlpha(lsf, ftReserve);
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
        if (xtPlusBeta == 0) {
            revert LiquidityIsZeroAfterTransaction();
        }
    }

    /// @notice Calculte the annual interest rate through curve parameters
    /// @param ltv The initial ltv of the market
    /// @param daysToMaturity The days until maturity
    /// @param ftPlusAlpha The FT token reserve plus alpha
    /// @param xtPlusBeta The XT token reserve plus beta
    /// @return apr The annual interest rate of the market
    function calcApr(
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
        int apr = numerator / denominator;
        if (apr > INT_64_MAX || apr < INT_64_MIN) {
            revert LiquidityIsZeroAfterTransaction();
        }
        return (numerator / denominator).toInt64();
    }

    /// @notice Calculate how much handling fee will be charged for this transaction
    /// @param ftReserve The FT token reserve of the market
    /// @param xtReserve The XT token reserve of the market
    /// @param newFtReserve The FT token reserve of the market after transaction
    /// @param newXtReserve The XT token reserve of the market after transaction
    /// @param feeRatio Transaction fee ratio
    ///                 There are different fee ratios for lending and borrowing
    /// @param ltv The initial ltv of the market
    /// @return feeAmt Transaction fee amount
    function calculateFee(
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

    /// @notice Internal helper function for calculating fees
    /// @param deltaFt Changes in FT token before and after the transaction
    /// @param deltaXt Changes in XT token before and after the transaction
    /// @param feeRatio Transaction fee ratio
    /// @param ltv The initial ltv of the market
    /// @return feeAmt Transaction fee amount
    function _calculateFeeInternal(
        uint256 deltaFt,
        uint256 deltaXt,
        uint32 feeRatio,
        uint32 ltv
    ) private pure returns (uint256 feeAmt) {
        uint l = deltaFt * Constants.DECIMAL_BASE + deltaXt * ltv;
        uint r = deltaXt * Constants.DECIMAL_BASE;

        if (l > r) {
            feeAmt = ((l - r) * feeRatio) / Constants.DECIMAL_BASE_SQ;
        } else {
            feeAmt = ((r - l) * feeRatio) / Constants.DECIMAL_BASE_SQ;
        }
    }

    /// @notice Calculate the reward to liquidity provider
    /// @param currentTime Current unix time
    /// @param openMarketTime The unix time when the market starts trading
    /// @param maturity The unix time of maturity date
    /// @param lpSupply The total supply of this lp token
    /// @param lpAmt The amount of withdraw lp
    /// @param totalReward The amount of bonus lp held in the market
    /// @return reward Number of lp's awarded
    function calculateLpReward(
        uint256 currentTime,
        uint256 openMarketTime,
        uint256 maturity,
        uint256 lpSupply,
        uint256 lpAmt,
        uint256 totalReward
    ) internal pure returns (uint256 reward) {
        uint t = (lpSupply - totalReward) *
            (2 * maturity - openMarketTime - currentTime);
        reward = ((totalReward * lpAmt) * (currentTime - openMarketTime)) / t;
    }

    /// @notice Calculate the changes in market reserves and apr after selling FT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function sellFt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint negB = ftPlusAlpha +
            (xtPlusBeta * config.initialLtv) /
            Constants.DECIMAL_BASE +
            params.amount;
        uint ac = ((xtPlusBeta * params.amount) * config.initialLtv) /
            Constants.DECIMAL_BASE;
        uint deltaXt = ((negB - (negB * negB - 4 * ac).sqrt()) *
            Constants.DECIMAL_BASE) / (config.initialLtv * 2);
        uint deltaFt = params.amount -
            (deltaXt * config.initialLtv) /
            Constants.DECIMAL_BASE;
        if (xtPlusBeta <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after selling negative FT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function sellNegFt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);

        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint b = ftPlusAlpha +
            (xtPlusBeta * config.initialLtv) /
            Constants.DECIMAL_BASE -
            params.amount;
        uint negAc = (xtPlusBeta * params.amount * config.initialLtv) /
            Constants.DECIMAL_BASE;

        uint deltaXt = ((((b * b + 4 * negAc)).sqrt() - b) *
            Constants.DECIMAL_BASE) / (config.initialLtv * 2);
        uint deltaFt = ftPlusAlpha -
            (ftPlusAlpha * xtPlusBeta) /
            (xtPlusBeta + deltaXt);
        if (ftPlusAlpha <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after selling XT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function sellXt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
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
                ((xtPlusBeta - params.amount) * config.initialLtv) /
                Constants.DECIMAL_BASE;
            // borrow stack space newXtReserve as ac
            uint negAc = ((((params.amount * xtPlusBeta) * config.initialLtv) /
                Constants.DECIMAL_BASE) * config.initialLtv) /
                Constants.DECIMAL_BASE;
            deltaXt =
                (((b * b + 4 * negAc).sqrt() - b) * Constants.DECIMAL_BASE) /
                (config.initialLtv * 2);
            deltaFt =
                ((params.amount - deltaXt) * config.initialLtv) /
                Constants.DECIMAL_BASE;
        }
        if (ftPlusAlpha <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after selling negative XT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function sellNegXt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint negB = ftPlusAlpha +
            ((xtPlusBeta + params.amount) * config.initialLtv) /
            Constants.DECIMAL_BASE;

        uint ac = ((((params.amount * xtPlusBeta) * config.initialLtv) /
            Constants.DECIMAL_BASE) * config.initialLtv) /
            Constants.DECIMAL_BASE;

        uint deltaXt = ((negB - (negB * negB - 4 * ac).sqrt()) *
            Constants.DECIMAL_BASE) / (config.initialLtv * 2);
        uint deltaFt = (ftPlusAlpha * xtPlusBeta) /
            (xtPlusBeta - deltaXt) -
            ftPlusAlpha;
        if (xtPlusBeta <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after selling buying FT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function buyFt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaXt = params.amount;
        uint deltaFt = ftPlusAlpha -
            (ftPlusAlpha * xtPlusBeta) /
            (xtPlusBeta + deltaXt);
        if (ftPlusAlpha <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after buying negative FT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function buyNegFt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaXt = params.amount;
        uint deltaFt = (ftPlusAlpha * xtPlusBeta) /
            (xtPlusBeta - deltaXt) -
            ftPlusAlpha;
        if (xtPlusBeta <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after buying XT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function buyXt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaFt = (params.amount * config.initialLtv) /
            Constants.DECIMAL_BASE;
        uint deltaXt = xtPlusBeta -
            (xtPlusBeta * ftPlusAlpha) /
            (ftPlusAlpha + deltaFt);
        if (xtPlusBeta <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha + deltaFt,
            xtPlusBeta - deltaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - deltaXt;
    }

    /// @notice Calculate the changes in market reserves and apr after buying negative XT tokens
    /// @param params Transaction data and token reserves
    /// @param config Market configuration data
    /// @return newFtReserve The FT token reserve of the market after transaction
    /// @return newXtReserve The XT token reserve of the market after transaction
    /// @return newApr The APR of the market after transaction
    function buyNegXt(
        TradeParams memory params,
        MarketConfig memory config
    )
        internal
        pure
        returns (uint256 newFtReserve, uint256 newXtReserve, int64 newApr)
    {
        uint ftPlusAlpha = calcFtPlusAlpha(config.lsf, params.ftReserve);
        uint xtPlusBeta = calcXtPlusBeta(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaFt = (params.amount * config.initialLtv) /
            Constants.DECIMAL_BASE;
        uint deltaXt = (xtPlusBeta * ftPlusAlpha) /
            (ftPlusAlpha - deltaFt) -
            xtPlusBeta;
        if (ftPlusAlpha <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            ftPlusAlpha - deltaFt,
            xtPlusBeta + deltaXt
        );

        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }
}
