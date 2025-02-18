// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Constants} from './Constants.sol';
import {MathLib, SafeCast} from './MathLib.sol';
import '../storage/TermMaxStorage.sol';

/**
 * @title The TermMax curve library
 * @author Term Structure Labs
 */
library TermMaxCurve {
    using SafeCast for uint256;
    using SafeCast for int256;
    using MathLib for *;

    /// @notice Calculate Curve cut id
    /// @param cuts Curve cut array
    /// @param xtReserve XT reserve
    /// @return cutId Curve cut id
    function calcCutId(CurveCut[] memory cuts, uint256 xtReserve) internal pure returns (uint256 cutId) {
        cutId = cuts.length;
        while (cutId > 0) {
            cutId--;
            if (xtReserve >= cuts[cutId].xtReserve) break;
        }
    }

    /// @notice Calculate interval properties
    /// @param daysToMaturity Days to maturity
    /// @param cut Curve cut
    /// @param xtReserve XT reserve
    /// @return liqSquare square of liquidity factor
    /// @return vXtReserve virtual XT reserve
    /// @return vFtReserve virtual FT reserve
    function calcIntervalProps(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut memory cut,
        uint256 xtReserve
    ) internal pure returns (uint256 liqSquare, uint256 vXtReserve, uint256 vFtReserve) {
        // reference: Eq.(8) in TermMax White Paper
        liqSquare =
            (cut.liqSquare * daysToMaturity * netInterestFactor) /
            (Constants.DAYS_IN_YEAR * Constants.DECIMAL_BASE);
        vXtReserve = xtReserve.plusInt256(cut.offset);
        vFtReserve = liqSquare / vXtReserve;
    }

    /// @notice Forward iteration over curve cuts
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param acc Input amount
    /// @param func Function to calculate delta values
    /// @return deltaXt Delta XT
    /// @return negDeltaFt Negative delta FT
    function cutsForwardIter(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 acc,
        function(uint, uint, uint, uint, uint, uint) internal pure returns (uint, uint) func
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        uint256 cutId = calcCutId(cuts, oriXtReserve);
        for (uint256 i = cutId; i < cuts.length; ++i) {
            uint256 xtReserve = oriXtReserve + deltaXt;
            (uint256 liqSquare, uint256 vXtReserve, uint256 vFtReserve) = calcIntervalProps(
                netInterestFactor,
                daysToMaturity,
                cuts[i],
                xtReserve
            );
            uint256 oriNegDeltaFt = negDeltaFt;
            (deltaXt, negDeltaFt) = func(liqSquare, vXtReserve, vFtReserve, deltaXt, negDeltaFt, acc);
            if (i < cuts.length - 1) {
                if (deltaXt == type(uint256).max) continue;
                if (oriXtReserve + deltaXt > cuts[i + 1].xtReserve) {
                    deltaXt = cuts[i + 1].xtReserve - oriXtReserve;
                    negDeltaFt = oriNegDeltaFt + vFtReserve - liqSquare / (vXtReserve + deltaXt);
                    continue;
                } else {
                    break;
                }
            }
        }
    }

    /// @notice Reverse iteration over curve cuts
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param acc Input amount
    /// @param func Function to calculate delta values
    /// @return negDeltaXt Negative delta XT
    /// @return deltaFt Delta FT
    function cutsReverseIter(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 acc,
        function(uint, uint, uint, uint, uint, uint) internal pure returns (uint, uint) func
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        uint256 cutId = calcCutId(cuts, oriXtReserve);
        for (uint256 i = cutId + 1; i > 0; i--) {
            uint256 idx = i - 1;
            uint256 xtReserve = oriXtReserve - negDeltaXt;
            (uint256 liqSquare, uint256 vXtReserve, uint256 vFtReserve) = calcIntervalProps(
                netInterestFactor,
                daysToMaturity,
                cuts[idx],
                xtReserve
            );
            (negDeltaXt, deltaFt) = func(liqSquare, vXtReserve, vFtReserve, negDeltaXt, deltaFt, acc);
            if (negDeltaXt == type(uint256).max) continue;
            if (oriXtReserve < negDeltaXt + cuts[idx].xtReserve) {
                negDeltaXt = oriXtReserve - cuts[idx].xtReserve;
                deltaFt = liqSquare / (vXtReserve - negDeltaXt) - vFtReserve;
            } else {
                break;
            }
        }
    }

    function buyExactXt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            outputAmount,
            buyExactXtStep
        );
    }

    function buyExactFt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            outputAmount,
            buyExactFtStep
        );
    }

    function buyExactXtStep(
        uint256,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriNegDeltaXt,
        uint256 oriDeltaFt,
        uint256 outputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        // reference: Section 4.2.3 in TermMax White Paper
        uint256 acc = outputAmount - (oriNegDeltaXt + oriDeltaFt);
        uint256 b = vXtReserve + vFtReserve + acc;
        uint256 c = vXtReserve * acc;

        uint256 segNegDeltaXt = (b - MathLib.sqrt(b * b - 4 * c)) / 2;
        negDeltaXt = oriNegDeltaXt + segNegDeltaXt;
        deltaFt = oriDeltaFt + acc - segNegDeltaXt;
    }

    function buyExactFtStep(
        uint256,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriDeltaXt,
        uint256 oriNegDeltaFt,
        uint256 outputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        //referece: Section 4.2.4 in TermMax White Paper
        uint256 acc = outputAmount - (oriNegDeltaFt + oriDeltaXt);
        uint256 b = vFtReserve + vXtReserve + acc;
        uint256 c = vFtReserve * acc;

        uint256 segNegDeltaFt = (b - MathLib.sqrt(b * b - 4 * c)) / 2;
        negDeltaFt = oriNegDeltaFt + segNegDeltaFt;
        deltaXt = oriDeltaXt + acc - segNegDeltaFt;
    }

    /// @notice Calculation for one step of buying FT
    /// @param liqSquare square of liquidity factor
    /// @param vXtReserve virtual XT reserve
    /// @param vFtReserve virtual FT reserve
    /// @param oriNegDeltaXt original negative delta XT
    /// @param oriDeltaFt original delta FT
    /// @param inputAmount input amount
    /// @return negDeltaXt Negative delta XT
    /// @return deltaFt Delta FT
    function buyXtStep(
        uint256 liqSquare,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriNegDeltaXt,
        uint256 oriDeltaFt,
        uint256 inputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        // reference: Eq.(10) in TermMax White Paper
        uint256 remainingInputAmt = inputAmount - oriDeltaFt;
        negDeltaXt = oriNegDeltaXt + vXtReserve - liqSquare / (vFtReserve + remainingInputAmt);
        deltaFt = inputAmount;
    }

    /// @notice Buy XT
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param inputAmount Input amount
    /// @return negDeltaXt Negative delta XT
    /// @return deltaFt Delta FT
    function buyXt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 inputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            inputAmount,
            buyXtStep
        );
    }

    /// @notice Calculation for one step of buying FT
    /// @param liqSquare square of liquidity factor
    /// @param vXtReserve virtual XT reserve
    /// @param vFtReserve virtual FT reserve
    /// @param oriDeltaXt original delta XT
    /// @param oriNegDeltaFt original negative delta FT
    /// @param inputAmount input amount
    /// @return deltaXt Delta XT
    /// @return negDeltaFt Negative delta FT
    function buyFtStep(
        uint256 liqSquare,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriDeltaXt,
        uint256 oriNegDeltaFt,
        uint256 inputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        // reference: Eq.(9) in TermMax White Paper
        uint256 remainingInputAmt = inputAmount - oriDeltaXt;
        negDeltaFt = oriNegDeltaFt + vFtReserve - liqSquare / (vXtReserve + remainingInputAmt);
        deltaXt = inputAmount;
    }

    /// @notice Buy FT
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param inputAmount Input amount
    /// @return deltaXt Delta XT
    /// @return negDeltaFt Negative delta FT
    function buyFt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 inputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            inputAmount,
            buyFtStep
        );
    }

    /// @notice Calculation for one step of selling XT
    /// @param vXtReserve virtual XT reserve
    /// @param vFtReserve virtual FT reserve
    /// @param oriDeltaXt original delta XT
    /// @param oriNegDeltaFt original negative delta FT
    /// @param inputAmount input amount
    /// @return deltaXt Delta XT
    /// @return negDeltaFt Negative delta FT
    function sellXtStep(
        uint256,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriDeltaXt,
        uint256 oriNegDeltaFt,
        uint256 inputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        // reference: Section 4.2.4 in TermMax White Paper
        uint256 negAcc = inputAmount - (oriDeltaXt + oriNegDeltaFt);
        uint256 b = vXtReserve + vFtReserve - negAcc;
        uint256 negC = vXtReserve * negAcc;

        uint256 segDeltaXt = (MathLib.sqrt(b * b + 4 * negC) - b) / 2;
        deltaXt = oriDeltaXt + segDeltaXt;
        negDeltaFt = oriNegDeltaFt + negAcc - segDeltaXt;
    }

    /// @notice Sell XT
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param inputAmount Input amount
    /// @return deltaXt Delta XT
    /// @return negDeltaFt Negative delta FT
    function sellXt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 inputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            inputAmount,
            sellXtStep
        );
    }

    /// @notice Calculation for one step of selling FT
    /// @param vXtReserve virtual XT reserve
    /// @param vFtReserve virtual FT reserve
    /// @param oriNegDeltaXt original negative delta XT
    /// @param oriDeltaFt original delta FT
    /// @param inputAmount input amount
    /// @return negDeltaXt Negative delta XT
    /// @return deltaFt Delta FT
    function sellFtStep(
        uint256,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriNegDeltaXt,
        uint256 oriDeltaFt,
        uint256 inputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        // reference: Section 4.2.3 in TermMax White Paper
        uint256 negAcc = inputAmount - (oriDeltaFt + oriNegDeltaXt);
        uint256 b = vFtReserve + vXtReserve - negAcc;
        uint256 negC = vFtReserve * negAcc;

        uint256 segDeltaFt = (MathLib.sqrt(b * b + 4 * negC) - b) / 2;
        deltaFt = oriDeltaFt + segDeltaFt;
        negDeltaXt = oriNegDeltaXt + negAcc - segDeltaFt;
    }

    /// @notice Sell FT
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param inputAmount Input amount
    /// @return negDeltaXt Negative delta XT
    /// @return deltaFt Delta FT
    function sellFt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 inputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            inputAmount,
            sellFtStep
        );
    }

    function sellFtForExactDebtToken(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            outputAmount,
            sellFtForExactDebtTokenStep
        );
    }

    function sellXtForExactDebtToken(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(
            netInterestFactor,
            daysToMaturity,
            cuts,
            oriXtReserve,
            outputAmount,
            sellXtForExactDebtTokenStep
        );
    }

    function sellFtForExactDebtTokenStep(
        uint256 liqSquare,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriNegDeltaXt,
        uint256 oriDeltaFt,
        uint256 outputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        // reference: Eq.(10) in TermMax White Paper
        uint256 remainingOutputAmt = outputAmount - oriNegDeltaXt;
        if (vXtReserve < remainingOutputAmt) return (type(uint256).max, type(uint256).max);
        deltaFt = oriDeltaFt + liqSquare / (vXtReserve - remainingOutputAmt) - vFtReserve;
        negDeltaXt = outputAmount;
    }

    function sellXtForExactDebtTokenStep(
        uint256 liqSquare,
        uint256 vXtReserve,
        uint256 vFtReserve,
        uint256 oriDeltaXt,
        uint256 oriNegDeltaFt,
        uint256 outputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        // reference: Eq.(9) in TermMax White Paper
        uint256 remainingOutputAmt = outputAmount - oriNegDeltaFt;
        if (vFtReserve < remainingOutputAmt) return (type(uint256).max, type(uint256).max);
        deltaXt = oriDeltaXt + liqSquare / (vFtReserve - remainingOutputAmt) - vXtReserve;
        negDeltaFt = outputAmount;
    }
}
