// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Constants} from "./Constants.sol";
import {MathLib, SafeCast} from "./MathLib.sol";
import "../storage/TermMaxStorage.sol";

import {console} from "forge-std/Script.sol";

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
    function calcCutId(
        CurveCut[] memory cuts,
        uint xtReserve
    ) internal pure returns (uint cutId) {
        cutId = cuts.length - 1;
        for (; cutId >= 0; cutId--) {
            if (xtReserve > cuts[cutId].xtReserve) break;
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
        uint daysToMaturity,
        CurveCut memory cut,
        uint xtReserve
    ) internal pure returns (uint liqSquare, uint vXtReserve, uint vFtReserve) {
        liqSquare = (cut.liqSquare * daysToMaturity) / Constants.DAYS_IN_YEAR;
        vXtReserve = xtReserve + cut.offset;
        vFtReserve = liqSquare / vXtReserve;
    }

    /// @notice Forward iteration over curve cuts
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param inputAmount Input amount
    /// @param func Function to calculate delta values
    /// @return deltaXt Delta XT
    /// @return negDeltaFt Negative delta FT
    function cutsForwardIter(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount,
        function(uint, uint, uint, uint, uint, uint)
            internal
            pure
            returns (uint, uint) func
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        uint cutId = calcCutId(cuts, oriXtReserve);
        for (uint i = cutId; i < cuts.length; ++i) {
            uint xtReserve = oriXtReserve + deltaXt;
            (
                uint liqSquare,
                uint vXtReserve,
                uint vFtReserve
            ) = calcIntervalProps(daysToMaturity, cuts[i], xtReserve);
            uint oriNegDeltaFt = negDeltaFt;
            (deltaXt, negDeltaFt) = func(
                liqSquare,
                vXtReserve,
                vFtReserve,
                deltaXt,
                negDeltaFt,
                inputAmount
            );
            if (i < cuts.length - 1) {
                if (oriXtReserve + deltaXt > cuts[i + 1].xtReserve) {
                    deltaXt = cuts[i + 1].xtReserve - oriXtReserve;
                    negDeltaFt =
                        oriNegDeltaFt +
                        vFtReserve -
                        liqSquare /
                        (vXtReserve + deltaXt);
                    continue;
                } else break;
            }
        }
    }

    /// @notice Reverse iteration over curve cuts
    /// @param daysToMaturity Days to maturity
    /// @param cuts Curve cut array
    /// @param oriXtReserve Original XT reserve
    /// @param inputAmount Input amount
    /// @param func Function to calculate delta values
    /// @return negDeltaXt Negative delta XT
    /// @return deltaFt Delta FT
    function cutsReverseIter(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount,
        function(uint, uint, uint, uint, uint, uint)
            internal
            pure
            returns (uint, uint) func
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        uint cutId = calcCutId(cuts, oriXtReserve);
        (negDeltaXt, deltaFt) = (0, 0);
        for (uint i = cutId + 1; i > 0; i--) {
            uint idx = i - 1;
            uint xtReserve = oriXtReserve - negDeltaXt;
            (
                uint liqSquare,
                uint vXtReserve,
                uint vFtReserve
            ) = calcIntervalProps(daysToMaturity, cuts[idx], xtReserve);
            uint oriDeltaFt = deltaFt;
            (negDeltaXt, deltaFt) = func(
                liqSquare,
                vXtReserve,
                vFtReserve,
                negDeltaXt,
                deltaFt,
                inputAmount
            );
            if (oriXtReserve < negDeltaXt + cuts[idx].xtReserve) {
                negDeltaXt = oriXtReserve - cuts[idx].xtReserve;
                deltaFt =
                    oriDeltaFt +
                    liqSquare /
                    (vXtReserve - negDeltaXt) -
                    vFtReserve;
            } else break;
        }
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
        uint liqSquare,
        uint vXtReserve,
        uint vFtReserve,
        uint oriNegDeltaXt,
        uint oriDeltaFt,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        uint remainingInputAmt = inputAmount - oriDeltaFt;
        negDeltaXt =
            oriNegDeltaXt +
            vXtReserve -
            liqSquare /
            (vFtReserve + remainingInputAmt);
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
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
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
        uint liqSquare,
        uint vXtReserve,
        uint vFtReserve,
        uint oriDeltaXt,
        uint oriNegDeltaFt,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        uint remainingInputAmt = inputAmount - oriDeltaXt;
        negDeltaFt =
            oriNegDeltaFt +
            vFtReserve -
            liqSquare /
            (vXtReserve + remainingInputAmt);
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
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(
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
        uint,
        uint vXtReserve,
        uint vFtReserve,
        uint oriDeltaXt,
        uint oriNegDeltaFt,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        uint negAcc = inputAmount - (oriDeltaXt + oriNegDeltaFt);
        uint b = vXtReserve + vFtReserve - negAcc;
        uint negC = vXtReserve * negAcc;

        uint segDeltaXt = (MathLib.sqrt(b * b + 4 * negC) - b) / 2;
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
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(
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
        uint,
        uint vXtReserve,
        uint vFtReserve,
        uint oriNegDeltaXt,
        uint oriDeltaFt,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        uint negAcc = inputAmount - (oriDeltaFt + oriNegDeltaXt);
        uint b = vFtReserve + vXtReserve - negAcc;
        uint negC = vFtReserve * negAcc;

        uint segDeltaFt = (MathLib.sqrt(b * b + 4 * negC) - b) / 2;
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
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(
            daysToMaturity,
            cuts,
            oriXtReserve,
            inputAmount,
            sellFtStep
        );
    }
}
