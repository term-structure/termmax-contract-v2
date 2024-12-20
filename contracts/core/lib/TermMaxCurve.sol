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

    function calcCutId(CurveCut[] memory cuts, uint xtReserve) internal pure returns (uint cutId) {
        cutId = 0;
        for (; cutId < cuts.length; cutId++) {
            if (xtReserve < cuts[cutId].offset) break;
        }
    }

    function calcIntervalEig(
        uint daysToMaturity,
        CurveCut memory cut,
        uint xtReserve
    ) internal pure returns (uint liqSquare, uint vXtReserve, uint vFtReserve) {
        liqSquare = (cut.liqSquare * Constants.DAYS_IN_YEAR) / daysToMaturity;
        vXtReserve = xtReserve + cut.offset;
        vFtReserve = liqSquare / vXtReserve;
    }

    function cutsForwardIter(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount,
        function(uint, uint, uint, uint, uint, uint) internal pure returns (uint, uint) func
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        uint cutId = calcCutId(cuts, oriXtReserve);
        (deltaXt, negDeltaFt) = (0, 0);
        for (uint i = cutId; i < cuts.length; ++i) {
            uint xtReserve = oriXtReserve + deltaXt;
            (uint liqSquare, uint vXtReserve, uint vFtReserve) = calcIntervalEig(daysToMaturity, cuts[i], xtReserve);
            uint oriNegDeltaFt = negDeltaFt;
            (deltaXt, negDeltaFt) = func(liqSquare, vXtReserve, vFtReserve, deltaXt, negDeltaFt, inputAmount);
            if (i < cuts.length - 1) {
                if (oriXtReserve + deltaXt > cuts[i + 1].xtReserve) {
                    deltaXt = cuts[i + 1].xtReserve - oriXtReserve;
                    negDeltaFt = oriNegDeltaFt + vFtReserve - liqSquare / cuts[i + 1].xtReserve;
                    continue;
                } else break;
            }
        }
    }

    function cutsReverseIter(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount,
        function(uint, uint, uint, uint, uint, uint) internal pure returns (uint, uint) func
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        uint cutId = calcCutId(cuts, oriXtReserve);
        (negDeltaXt, deltaFt) = (0, 0);
        for (uint i = cutId; i >= 0; --i) {
            uint xtReserve = oriXtReserve - negDeltaXt;
            (uint liqSquare, uint vXtReserve, uint vFtReserve) = calcIntervalEig(daysToMaturity, cuts[i], xtReserve);
            uint oriDeltaFt = deltaFt;
            (negDeltaXt, deltaFt) = func(liqSquare, vXtReserve, vFtReserve, negDeltaXt, deltaFt, inputAmount);
            if (oriXtReserve < negDeltaXt + cuts[i].xtReserve) {
                negDeltaXt = oriXtReserve - cuts[i].xtReserve;
                deltaFt = oriDeltaFt + liqSquare / cuts[i + 1].xtReserve - vFtReserve;
                continue;
            } else break;
        }
    }

    function buyXtStep(
        uint liqSquare,
        uint vXtReserve,
        uint vFtReserve,
        uint oriNegDeltaXt,
        uint oriDeltaFt,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        uint remainingInputAmt = inputAmount - oriDeltaFt;
        negDeltaXt = oriNegDeltaXt + vXtReserve - liqSquare / (vFtReserve + remainingInputAmt);
        deltaFt = inputAmount;
    }

    function buyXt(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(daysToMaturity, cuts, oriXtReserve, inputAmount, buyXtStep);
    }

    function buyFtStep(
        uint liqSquare,
        uint vXtReserve,
        uint vFtReserve,
        uint oriDeltaXt,
        uint oriNegDeltaFt,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        uint remainingInputAmt = inputAmount - oriDeltaXt;
        negDeltaFt = oriNegDeltaFt + vFtReserve - liqSquare / (vXtReserve + remainingInputAmt);
        deltaXt = inputAmount;
    }

    function buyFt(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(daysToMaturity, cuts, oriXtReserve, inputAmount, buyFtStep);
    }

    function sellXtStep(
        uint liqSquare,
        uint vXtReserve,
        uint vFtReserve,
        uint oriDeltaXt,
        uint oriNegDeltaFt,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        uint negAcc = inputAmount - (oriDeltaXt + oriNegDeltaFt);
        uint negB = vXtReserve + vFtReserve - negAcc;
        uint negC = vXtReserve * negAcc;

        uint segDeltaXt = (negB + MathLib.sqrt(negB * negB + 4 * negC)) / 2;
        deltaXt = oriDeltaXt + segDeltaXt;
        negDeltaFt = oriNegDeltaFt + negAcc - segDeltaXt;
    }

    function sellXt(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint deltaXt, uint negDeltaFt) {
        (deltaXt, negDeltaFt) = cutsForwardIter(daysToMaturity, cuts, oriXtReserve, inputAmount, sellXtStep);
    }

    function sellFtStep(
        uint liqSquare,
        uint vXtReserve,
        uint vFtReserve,
        uint oriNegDeltaXt,
        uint oriDeltaFt,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        uint negAcc = inputAmount - (oriDeltaFt + oriNegDeltaXt);
        uint negB = vFtReserve + vXtReserve - negAcc;
        uint negC = vFtReserve * negAcc;

        uint segDeltaFt = (negB + MathLib.sqrt(negB * negB + 4 * negC)) / 2;
        deltaFt = oriDeltaFt + segDeltaFt;
        negDeltaXt = oriNegDeltaXt + negAcc - segDeltaFt;
    }

    function sellFt(
        uint daysToMaturity,
        CurveCut[] memory cuts,
        uint oriXtReserve,
        uint inputAmount
    ) internal pure returns (uint negDeltaXt, uint deltaFt) {
        (negDeltaXt, deltaFt) = cutsReverseIter(daysToMaturity, cuts, oriXtReserve, inputAmount, sellFtStep);
    }
}
