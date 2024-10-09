// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library YAMarketCurve {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint32 public constant DECIMAL_BASE = 1e8;
    uint64 public constant DECIMAL_BASE_SQRT = 1e16;
    uint16 public constant DAYS_IN_YEAR = 365;
    uint32 public constant SECONDS_IN_DAY = 86400;

    function calcYpPlusAlpha(
        uint32 gamma,
        uint256 ypReserve
    ) public pure returns (uint256) {
        return ypReserve.mulDiv(gamma, DECIMAL_BASE).toUint128();
    }

    function calcYaPlusBeta(
        uint32 gamma,
        uint32 ltv,
        uint256 daysToMaturity,
        int64 apy,
        uint128 ypReserve
    ) public pure returns (uint256 yaPlusBeta) {
        // yaReserve + beta = (ypReserve + alpha)/(1 + apy*dayToMaturity/365 - lvt)
        uint ypPlusAlpha = calcYpPlusAlpha(gamma, ypReserve);
        uint absoluteApy = int256(apy).toUint256();
        // Use DECIMAL_BASE to solve the problem of precision loss
        if (apy >= 0) {
            yaPlusBeta =
                (ypPlusAlpha * DECIMAL_BASE_SQRT) /
                (DECIMAL_BASE +
                    absoluteApy.mulDiv(daysToMaturity, DAYS_IN_YEAR) -
                    ltv) /
                DECIMAL_BASE;
        } else {
            yaPlusBeta =
                (ypPlusAlpha * DECIMAL_BASE_SQRT) /
                (DECIMAL_BASE -
                    absoluteApy.mulDiv(daysToMaturity, DAYS_IN_YEAR) -
                    ltv) /
                DECIMAL_BASE;
        }
    }

    function _calcSellNegYp(
        uint32 gamma,
        uint32 ltv,
        uint256 daysToMaturity,
        uint128 negAmount,
        uint128 ypReserve,
        uint128 yaReserve,
        int64 apy
    ) internal pure returns (uint128, uint128, int64) {
        uint ypPlusAlpha = calcYpPlusAlpha(gamma, ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            gamma,
            ltv,
            daysToMaturity,
            apy,
            ypReserve
        );
        uint b = ypPlusAlpha + yaPlusBeta.mulDiv(ltv, DECIMAL_BASE) - negAmount;
        uint256 negAc = yaPlusBeta.mulDiv(negAmount * ltv, DECIMAL_BASE);
        uint256 deltaYa = (((b.sqrt() + 4 * negAc).sqrt() - b) * DECIMAL_BASE) /
            ltv /
            2;
        uint256 deltaYp = ypPlusAlpha -
            ypPlusAlpha.mulDiv(yaPlusBeta, yaPlusBeta + deltaYa);

        apy = calcApy(
            ltv,
            daysToMaturity,
            ypPlusAlpha - deltaYp,
            yaPlusBeta + deltaYa
        );
        return (
            (ypReserve - deltaYp).toUint128(),
            (yaReserve + deltaYa).toUint128(),
            apy
        );
    }

    function calcApy(
        uint32 ltv,
        uint256 daysToMaturity,
        uint256 ypPlusAlpha,
        uint256 yaPlusBeta
    ) public pure returns (int64) {
        uint256 l = DECIMAL_BASE *
            DAYS_IN_YEAR *
            (ypPlusAlpha * DECIMAL_BASE + yaPlusBeta * ltv);
        uint256 r = yaPlusBeta * DAYS_IN_YEAR * DECIMAL_BASE_SQRT;
        int256 numerator = l > r ? int256(l - r) : -int256(r - l);
        return
            (numerator /
                (uint256(yaPlusBeta) * daysToMaturity * DECIMAL_BASE)
                    .toInt256()).toInt64();
    }
}
