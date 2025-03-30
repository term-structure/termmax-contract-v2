// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Constants} from "./Constants.sol";
import {MathLib, SafeCast} from "./MathLib.sol";
import {CurveCut} from "../storage/TermMaxStorage.sol";

/**
 * @title The TermMax curve library
 * @author Term Structure Labs
 */
library TermMaxCurve {
    using SafeCast for uint256;
    using SafeCast for int256;
    using MathLib for *;

    error InsufficientLiquidity();

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
            (cut.liqSquare * daysToMaturity * netInterestFactor) / (Constants.DAYS_IN_YEAR * Constants.DECIMAL_BASE);
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
        function(int, int, int, int, int, int) internal pure returns (int, int) func
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        uint256 cutId = calcCutId(cuts, oriXtReserve);
        for (uint256 i = cutId; i < cuts.length; ++i) {
            uint256 xtReserve = oriXtReserve + deltaXt;
            (uint256 liqSquare, uint256 vXtReserve, uint256 vFtReserve) =
                calcIntervalProps(netInterestFactor, daysToMaturity, cuts[i], xtReserve);
            {
                (int256 dX, int256 nF) = func(
                    liqSquare.toInt256(),
                    vXtReserve.toInt256(),
                    vFtReserve.toInt256(),
                    deltaXt.toInt256(),
                    -negDeltaFt.toInt256(),
                    acc.toInt256()
                );

                if (i != cuts.length - 1) {
                    if (
                        (dX < deltaXt.toInt256() || nF < negDeltaFt.toInt256())
                            || oriXtReserve + uint256(dX) > cuts[i + 1].xtReserve
                    ) {
                        deltaXt = cuts[i + 1].xtReserve - oriXtReserve;
                        negDeltaFt += vFtReserve - liqSquare / (vXtReserve + (cuts[i + 1].xtReserve - xtReserve));
                        continue;
                    } else {
                        return (uint256(dX), uint256(nF));
                    }
                } else if (dX >= deltaXt.toInt256() && nF >= negDeltaFt.toInt256()) {
                    return (uint256(dX), uint256(nF));
                }
            }
        }
        revert InsufficientLiquidity();
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
        function(int, int, int, int, int, int) internal pure returns (int, int) func
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        uint256 cutId = calcCutId(cuts, oriXtReserve);
        for (uint256 i = cutId + 1; i > 0; i--) {
            uint256 idx = i - 1;
            uint256 xtReserve = oriXtReserve - negDeltaXt;
            (uint256 liqSquare, uint256 vXtReserve, uint256 vFtReserve) =
                calcIntervalProps(netInterestFactor, daysToMaturity, cuts[idx], xtReserve);
            {
                (int256 nX, int256 dF) = func(
                    liqSquare.toInt256(),
                    vXtReserve.toInt256(),
                    vFtReserve.toInt256(),
                    -negDeltaXt.toInt256(),
                    deltaFt.toInt256(),
                    acc.toInt256()
                );

                if (
                    (nX < negDeltaXt.toInt256() || dF < deltaFt.toInt256())
                        || oriXtReserve < uint256(nX) + cuts[idx].xtReserve
                ) {
                    negDeltaXt = oriXtReserve - cuts[idx].xtReserve;
                    deltaFt += liqSquare / (vXtReserve - (xtReserve - cuts[idx].xtReserve)) - vFtReserve;
                    continue;
                } else {
                    return (uint256(nX), uint256(dF));
                }
            }
        }
        revert InsufficientLiquidity();
    }

    function buyExactXt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        (negDeltaXt, deltaFt) =
            cutsReverseIter(netInterestFactor, daysToMaturity, cuts, oriXtReserve, outputAmount, buyExactXtStep);
    }

    function buyExactFt(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 deltaXt, uint256 negDeltaFt) {
        (deltaXt, negDeltaFt) =
            cutsForwardIter(netInterestFactor, daysToMaturity, cuts, oriXtReserve, outputAmount, buyExactFtStep);
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
        (negDeltaXt, deltaFt) =
            cutsReverseIter(netInterestFactor, daysToMaturity, cuts, oriXtReserve, inputAmount, buyXtStep);
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
        (deltaXt, negDeltaFt) =
            cutsForwardIter(netInterestFactor, daysToMaturity, cuts, oriXtReserve, inputAmount, buyFtStep);
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
        (deltaXt, negDeltaFt) =
            cutsForwardIter(netInterestFactor, daysToMaturity, cuts, oriXtReserve, inputAmount, sellXtStep);
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
        (negDeltaXt, deltaFt) =
            cutsReverseIter(netInterestFactor, daysToMaturity, cuts, oriXtReserve, inputAmount, sellFtStep);
    }

    function sellFtForExactDebtToken(
        uint256 netInterestFactor,
        uint256 daysToMaturity,
        CurveCut[] memory cuts,
        uint256 oriXtReserve,
        uint256 outputAmount
    ) internal pure returns (uint256 negDeltaXt, uint256 deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
            netInterestFactor, daysToMaturity, cuts, oriXtReserve, outputAmount, sellFtForExactDebtTokenStep
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
            netInterestFactor, daysToMaturity, cuts, oriXtReserve, outputAmount, sellXtForExactDebtTokenStep
        );
    }

    function sellTokenStepBase(
        int256,
        int256 vLhsReserve,
        int256 vRhsReserve,
        int256 oriDeltaLhs,
        int256 oriDeltaRhs,
        int256 inputAmt
    ) internal pure returns (int256 deltaLhs, int256 negDeltaRhs) {
        // reference: Section 4.2.3, Section 4.2.4 in TermMax White Paper
        int256 acc = (oriDeltaLhs - oriDeltaRhs) - inputAmt;
        int256 b = vLhsReserve + vRhsReserve + acc;
        int256 c = vLhsReserve * acc;

        int256 segDeltaLhs = (MathLib.sqrt((b * b - 4 * c).toUint256()).toInt256() - b) / 2;
        deltaLhs = oriDeltaLhs + segDeltaLhs;
        negDeltaRhs = -oriDeltaRhs - acc - segDeltaLhs;
    }

    function buyTokenStepBase(
        int256 liqSquare,
        int256 vlhsReserve,
        int256 vRhsReserve,
        int256 oriDeltalhs,
        int256 oriDeltaRhs,
        int256 inputAmt
    ) internal pure returns (int256 negDeltalhs, int256 deltaRhs) {
        // reference: Eq.(9), Eq.(10) in TermMax White Paper
        int256 remainingInputAmt = inputAmt - oriDeltaRhs;
        negDeltalhs = -oriDeltalhs + vlhsReserve - liqSquare / (vRhsReserve + remainingInputAmt);
        deltaRhs = inputAmt;
    }

    function buyXtStep(
        int256 liqSquare,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 inputAmt
    ) internal pure returns (int256 negDeltaXt, int256 deltaFt) {
        (negDeltaXt, deltaFt) = buyTokenStepBase(liqSquare, vXtReserve, vFtReserve, oriDeltaXt, oriDeltaFt, inputAmt);
    }

    function buyFtStep(
        int256 liqSquare,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 inputAmt
    ) internal pure returns (int256 deltaXt, int256 negDeltaFt) {
        (negDeltaFt, deltaXt) = buyTokenStepBase(liqSquare, vFtReserve, vXtReserve, oriDeltaFt, oriDeltaXt, inputAmt);
    }

    function sellXtStep(
        int256,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 inputAmt
    ) internal pure returns (int256 deltaXt, int256 negDeltaFt) {
        (deltaXt, negDeltaFt) = sellTokenStepBase(0, vXtReserve, vFtReserve, oriDeltaXt, oriDeltaFt, inputAmt);
    }

    function sellFtStep(
        int256,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 inputAmt
    ) internal pure returns (int256 negDeltaXt, int256 deltaFt) {
        (deltaFt, negDeltaXt) = sellTokenStepBase(0, vFtReserve, vXtReserve, oriDeltaFt, oriDeltaXt, inputAmt);
    }

    function buyExactXtStep(
        int256,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 outputAmt
    ) internal pure returns (int256, int256) {
        (int256 deltaXt, int256 negDeltaFt) = sellXtStep(0, vXtReserve, vFtReserve, oriDeltaXt, oriDeltaFt, -outputAmt);
        return (-deltaXt, -negDeltaFt);
    }

    function buyExactFtStep(
        int256,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 outputAmt
    ) internal pure returns (int256, int256) {
        (int256 negDeltaXt, int256 deltaFt) = sellFtStep(0, vXtReserve, vFtReserve, oriDeltaXt, oriDeltaFt, -outputAmt);
        return (-negDeltaXt, -deltaFt);
    }

    function sellFtForExactDebtTokenStep(
        int256 liqSquare,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 outputAmt
    ) internal pure returns (int256, int256) {
        (int256 deltaXt, int256 negDeltaFt) =
            buyFtStep(liqSquare, vXtReserve, vFtReserve, oriDeltaXt, oriDeltaFt, -outputAmt);
        return (-deltaXt, -negDeltaFt);
    }

    function sellXtForExactDebtTokenStep(
        int256 liqSquare,
        int256 vXtReserve,
        int256 vFtReserve,
        int256 oriDeltaXt,
        int256 oriDeltaFt,
        int256 outputAmt
    ) internal pure returns (int256, int256) {
        (int256 negDeltaXt, int256 deltaFt) =
            buyXtStep(liqSquare, vXtReserve, vFtReserve, oriDeltaXt, oriDeltaFt, -outputAmt);
        return (-negDeltaXt, -deltaFt);
    }
}
