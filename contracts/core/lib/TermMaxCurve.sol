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
            // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/liquidity-operations-l#lo1-provide-liquidity
            // Ref: Eq.L-3,L-4 in the AMM Model section of docs
            lpOutAmt = (tokenIn * lpTotalSupply) / tokenReserve;
        }
    }

    /// @notice Calculate how many tokens should be transfer to the liquidity provider
    /// @param lpAmt The amount of lp to withdraw
    /// @param lpTotalSupply The total supply of this lp token
    /// @param lpReserve The lp token balance of market
    /// @param tokenReserve The token balance of market
    /// @param config Market configuration data
    /// @return tokenAmt The amount of tokens transfer to the liquidity provider
    function calculateLpWithReward(
        uint256 lpAmt,
        uint256 lpTotalSupply,
        uint256 lpReserve,
        uint256 tokenReserve,
        uint256 currentTime,
        MarketConfig memory config
    ) internal pure returns (uint256 tokenAmt) {
        uint reward = TermMaxCurve.calculateLpReward(
            currentTime,
            config.openTime,
            config.maturity,
            lpTotalSupply,
            lpAmt,
            lpReserve
        );
        lpAmt += reward;
        tokenAmt = (lpAmt * tokenReserve) / lpTotalSupply;
    }

    /// @notice Calculte the virtual FT token reserve
    /// @param lsf The liquidity scaling factor (variable name for gamma in the formula)
    /// @param ftReserve The FT token reserve of the market
    /// @return virtualFtReserve The virtual FT token reserve
    function calcVirtualFtReserve(
        uint32 lsf,
        uint256 ftReserve
    ) internal pure returns (uint256 virtualFtReserve) {
        virtualFtReserve = (ftReserve * Constants.DECIMAL_BASE) / lsf;
        if (virtualFtReserve == 0) {
            revert LiquidityIsZeroAfterTransaction();
        }
    }

    /// @notice Calculte the virtual XT token reserve
    /// @param lsf The liquidity scaling factor
    /// @param ltv The initial ltv of the market (variable name for gamma in the formula)
    /// @param daysToMaturity The days until maturity
    /// @param apr The annual interest rate of the market
    /// @param ftReserve The FT token reserve of the market
    /// @return virtualXtReserve The virtual XT token reserve
    function calcVirtualXtReserve(
        uint32 lsf,
        uint32 ltv,
        uint256 daysToMaturity,
        int64 apr,
        uint256 ftReserve
    ) internal pure returns (uint256 virtualXtReserve) {
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/definition-d#price
        // Ref: Eq. D-4 in the AMM Model section of docs
        // virtualXtReserve = virtualFtReserve / (1 + apr * dayToMaturity / 365 - lvt)
        //                  = virtualFtReserve * 365 / (365 + apr * dayToMaturity - ltv * 365)
        uint virtualFtReserve = calcVirtualFtReserve(lsf, ftReserve);
        // Use Constants.DECIMAL_BASE to prevent precision loss
        if (apr >= 0) {
            virtualXtReserve =
                (virtualFtReserve *
                    Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR) /
                (Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR +
                    uint(int(apr)) *
                    daysToMaturity -
                    ltv *
                    Constants.DAYS_IN_YEAR);
        } else {
            virtualXtReserve =
                (virtualFtReserve *
                    Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR) /
                (Constants.DECIMAL_BASE *
                    Constants.DAYS_IN_YEAR -
                    uint(int(-apr)) *
                    daysToMaturity -
                    ltv *
                    Constants.DAYS_IN_YEAR);
        }
        if (virtualXtReserve == 0) {
            revert LiquidityIsZeroAfterTransaction();
        }
    }

    /// @notice Calculte the annual interest rate through curve parameters
    /// @param ltv The initial ltv of the market
    /// @param daysToMaturity The days until maturity
    /// @param virtualFtReserve The virtual FT token reserve
    /// @param virtualXtReserve The virtual XT token reserve
    /// @return apr The annual interest rate of the market
    function calcApr(
        uint32 ltv,
        uint256 daysToMaturity,
        uint256 virtualFtReserve,
        uint256 virtualXtReserve
    ) internal pure returns (int64) {
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/definition-d#apr-annual-percentage-rate
        // Ref: Eq. D-6 in the AMM Model section of docs
        uint leftNumerator = Constants.DECIMAL_BASE *
            Constants.DAYS_IN_YEAR *
            (virtualFtReserve *
                Constants.DECIMAL_BASE +
                virtualXtReserve *
                ltv);
        uint rightNumerator = virtualXtReserve *
            Constants.DAYS_IN_YEAR *
            Constants.DECIMAL_BASE_SQ;
        int numerator = leftNumerator > rightNumerator
            ? int(leftNumerator - rightNumerator)
            : -int(rightNumerator - leftNumerator);
        int denominator = (virtualXtReserve *
            daysToMaturity *
            Constants.DECIMAL_BASE).toInt256();
        int apr = numerator / denominator;
        if (apr > INT_64_MAX || apr < INT_64_MIN) {
            revert LiquidityIsZeroAfterTransaction();
        }
        return (numerator / denominator).toInt64();
    }

    /// @notice Calculate how much fee will be charged for this transaction
    /// @param ftReserve The FT token reserve of the market
    /// @param xtReserve The XT token reserve of the market
    /// @param newFtReserve The FT token reserve of the market after transaction
    /// @param newXtReserve The XT token reserve of the market after transaction
    /// @param feeRatio Transaction fee ratio
    ///                 There are different fee ratios for lending (buy FT/sell XT) and borrowing (buy XT/sell FT)
    /// @param ltv The initial ltv of the market
    /// @return feeAmt Transaction fee amount
    function calculateTxFee(
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
        feeAmt = _calculateTxFeeInternal(deltaFt, deltaXt, feeRatio, ltv);
    }

    /// @notice Internal helper function for calculating fees
    /// @param deltaFt Changes in FT token before and after the transaction
    /// @param deltaXt Changes in XT token before and after the transaction
    /// @param feeRatio Transaction fee ratio
    /// @param ltv The initial ltv of the market
    /// @return feeAmt Transaction fee amount
    function _calculateTxFeeInternal(
        uint256 deltaFt,
        uint256 deltaXt,
        uint32 feeRatio,
        uint32 ltv
    ) private pure returns (uint256 feeAmt) {
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/fee-operations-f
        // Ref: Eq.F-1 in the AMM Model section of docs
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
    /// @param totalReward The amount of accumulated lp token reward of the market
    /// @return reward Number of lp token awarded
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp4-sell-ft-for-underlying
        // Ref: Eq.S-16 in the AMM Model section of docs
        uint negB = virtualFtReserve +
            (virtualXtReserve * config.initialLtv) /
            Constants.DECIMAL_BASE +
            params.amount;
        uint ac = ((virtualXtReserve * params.amount) * config.initialLtv) /
            Constants.DECIMAL_BASE;
        // Ref: Eq.S-13 in the AMM Model section of docs
        uint deltaXt = ((negB - (negB * negB - 4 * ac).sqrt()) *
            Constants.DECIMAL_BASE) / (config.initialLtv * 2);
        // Ref: Eq.S-14 in the AMM Model section of docs
        uint deltaFt = params.amount -
            (deltaXt * config.initialLtv) /
            Constants.DECIMAL_BASE;
        if (virtualXtReserve <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve + deltaFt,
            virtualXtReserve - deltaXt
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp8-sell-negative-ft-for-negative-underlying
        // Ref: Eq.S-32 in the AMM Model section of docs
        uint b = virtualFtReserve +
            (virtualXtReserve * config.initialLtv) /
            Constants.DECIMAL_BASE -
            params.amount;
        uint negAc = (virtualXtReserve * params.amount * config.initialLtv) /
            Constants.DECIMAL_BASE;
        // Ref: Eq.S-29 in the AMM Model section of docs
        uint deltaXt = ((((b * b + 4 * negAc)).sqrt() - b) *
            Constants.DECIMAL_BASE) / (config.initialLtv * 2);
        // Ref: Eq.S-30 in the AMM Model section of docs
        uint deltaFt = virtualFtReserve -
            (virtualFtReserve * virtualXtReserve) /
            (virtualXtReserve + deltaXt);
        if (virtualFtReserve <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve - deltaFt,
            virtualXtReserve + deltaXt
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        uint deltaXt;
        uint deltaFt;
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp3-sell-xt-for-underlying
        {
            // Ref: Eq.S-12 in the AMM Model section of docs
            uint b = virtualFtReserve +
                ((virtualXtReserve - params.amount) * config.initialLtv) /
                Constants.DECIMAL_BASE;
            uint negAc = ((((params.amount * virtualXtReserve) *
                config.initialLtv) / Constants.DECIMAL_BASE) *
                config.initialLtv) / Constants.DECIMAL_BASE;
            // Ref: Eq.S-9 in the AMM Model section of docs
            deltaXt =
                (((b * b + 4 * negAc).sqrt() - b) * Constants.DECIMAL_BASE) /
                (config.initialLtv * 2);
            //Ref: Eq.S-10 in the AMM Model section of docs
            deltaFt =
                ((params.amount - deltaXt) * config.initialLtv) /
                Constants.DECIMAL_BASE;
        }
        if (virtualFtReserve <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve - deltaFt,
            virtualXtReserve + deltaXt
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp7-sell-negative-xt-for-negative-underlying
        // Ref: Eq.S-28 in the AMM Model section of docs
        uint negB = virtualFtReserve +
            ((virtualXtReserve + params.amount) * config.initialLtv) /
            Constants.DECIMAL_BASE;
        uint ac = ((((params.amount * virtualXtReserve) * config.initialLtv) /
            Constants.DECIMAL_BASE) * config.initialLtv) /
            Constants.DECIMAL_BASE;
        // Ref: Eq.S-25 in the AMM Model section of docs
        uint deltaXt = ((negB - (negB * negB - 4 * ac).sqrt()) *
            Constants.DECIMAL_BASE) / (config.initialLtv * 2);
        // Ref: Eq.S-26 in the AMM Model section of docs
        uint deltaFt = (virtualFtReserve * virtualXtReserve) /
            (virtualXtReserve - deltaXt) -
            virtualFtReserve;
        if (virtualXtReserve <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve + deltaFt,
            virtualXtReserve - deltaXt
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp2-buy-ft-with-underlying
        // Ref: Eq.S-6 in the AMM Model section of docs
        uint sigmaXt = params.amount;
        // Ref: Eq.S-7 in the AMM Model section of docs
        uint deltaFt = virtualFtReserve -
            (virtualFtReserve * virtualXtReserve) /
            (virtualXtReserve + sigmaXt);
        if (virtualFtReserve <= deltaFt || deltaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve - deltaFt,
            virtualXtReserve + sigmaXt
        );
        newFtReserve = params.ftReserve - deltaFt;
        newXtReserve = params.xtReserve + sigmaXt;
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp6-buy-negative-ft-with-negative-underlying
        // Ref: Eq.S-22 in the AMM Model section of docs
        uint sigmaXt = params.amount;
        // Ref: Eq.S-23 in the AMM Model section of docs
        uint deltaFt = (virtualFtReserve * virtualXtReserve) /
            (virtualXtReserve - sigmaXt) -
            virtualFtReserve;
        if (virtualXtReserve <= sigmaXt || sigmaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve + deltaFt,
            virtualXtReserve - sigmaXt
        );
        newFtReserve = params.ftReserve + deltaFt;
        newXtReserve = params.xtReserve - sigmaXt;
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp1-buy-xt-with-underlying
        // Ref: Eq.S-1 in the AMM Model section of docs
        uint sigmaFt = (params.amount * config.initialLtv) /
            Constants.DECIMAL_BASE;
        // Ref: Eq.S-3 in the AMM Model section of docs
        uint deltaXt = virtualXtReserve -
            (virtualXtReserve * virtualFtReserve) /
            (virtualFtReserve + sigmaFt);
        if (virtualXtReserve <= deltaXt || deltaXt >= params.xtReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/definition-d#apr-annual-percentage-rate
        // Ref: Eq.D-5 in the AMM Model section of docs
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve + sigmaFt,
            virtualXtReserve - deltaXt
        );
        newFtReserve = params.ftReserve + sigmaFt;
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
        // Calculate the virtual FT reserves before the transaction
        uint virtualFtReserve = calcVirtualFtReserve(
            config.lsf,
            params.ftReserve
        );
        // Calculate the virtual XT reserves before the transaction
        uint virtualXtReserve = calcVirtualXtReserve(
            config.lsf,
            config.initialLtv,
            params.daysToMaturity,
            config.apr,
            params.ftReserve
        );
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/swap-operations-s#sp5-buy-negative-xt-with-negative-underlying
        // Ref: Eq.S-17 in the AMM Model section of docs
        uint sigmaFt = (params.amount * config.initialLtv) /
            Constants.DECIMAL_BASE;
        // Ref: Eq.S-19 in the AMM Model section of docs
        uint deltaXt = (virtualXtReserve * virtualFtReserve) /
            (virtualFtReserve - sigmaFt) -
            virtualXtReserve;
        if (virtualFtReserve <= sigmaFt || sigmaFt >= params.ftReserve) {
            revert LiquidityIsZeroAfterTransaction();
        }
        newApr = calcApr(
            config.initialLtv,
            params.daysToMaturity,
            virtualFtReserve - sigmaFt,
            virtualXtReserve + deltaXt
        );

        newFtReserve = params.ftReserve - sigmaFt;
        newXtReserve = params.xtReserve + deltaXt;
    }
}
