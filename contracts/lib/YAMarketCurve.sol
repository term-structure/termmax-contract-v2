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
        uint256 ypReserve
    ) public pure returns (uint256 yaPlusBeta) {
        // yaReserve + beta = (ypReserve + alpha)/(1 + apy*dayToMaturity/365 - lvt)
        uint ypPlusAlpha = calcYpPlusAlpha(gamma, ypReserve);
        uint absoluteApy = int(apy).toUint256();
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

    function _sellNegYpApy(
        uint256 negAmount,
        uint256 ypReserve,
        uint256 daysToMaturity,
        uint32 gamma,
        uint32 ltv,
        int64 apy
    ) internal pure returns (int64) {
        uint ypPlusAlpha = calcYpPlusAlpha(gamma, ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            gamma,
            ltv,
            daysToMaturity,
            apy,
            ypReserve
        );
        uint b = ypPlusAlpha + yaPlusBeta.mulDiv(ltv, DECIMAL_BASE) - negAmount;
        uint negAc = yaPlusBeta.mulDiv(negAmount * ltv, DECIMAL_BASE);
        uint deltaYa = (((b.sqrt() + 4 * negAc).sqrt() - b) * DECIMAL_BASE) /
            ltv /
            2;
        uint deltaYp = ypPlusAlpha -
            ypPlusAlpha.mulDiv(yaPlusBeta, yaPlusBeta + deltaYa);

        return
            calcApy(
                ltv,
                daysToMaturity,
                ypPlusAlpha - deltaYp,
                yaPlusBeta + deltaYa
            );
    }

    function _sellNegYaApy(
        uint256 negAmount,
        uint256 ypReserve,
        uint256 daysToMaturity,
        uint32 gamma,
        uint32 ltv,
        int64 apy
    ) internal pure returns (int64) {
        uint ypPlusAlpha = calcYpPlusAlpha(gamma, ypReserve);
        uint yaPlusBeta = calcYaPlusBeta(
            gamma,
            ltv,
            daysToMaturity,
            apy,
            ypReserve
        );
        uint negB = ypPlusAlpha +
            (yaPlusBeta + negAmount).mulDiv(ltv, DECIMAL_BASE);

        uint ac = (negAmount * yaPlusBeta).mulDiv(
            uint(ltv).sqrt(),
            DECIMAL_BASE_SQRT
        );

        uint deltaYa = ((negB - (negB.sqrt() - 4 * ac).sqrt()) * DECIMAL_BASE) /
            ltv /
            2;
        uint deltaYp = ypPlusAlpha.mulDiv(yaPlusBeta, (yaPlusBeta - deltaYa)) -
            ypPlusAlpha;
        return
            calcApy(
                ltv,
                daysToMaturity,
                uint128(ypPlusAlpha + deltaYp),
                uint128(yaPlusBeta - deltaYa)
            );
    }

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
        return
            (numerator /
                (uint256(yaPlusBeta) * daysToMaturity * DECIMAL_BASE)
                    .toInt256()).toInt64();
    }

    // calculate the lp value user will received when provide liquidity
    function _predictLpOut(
        uint256 cashAmt,
        uint256 daysTomaturity,
        uint256 ypReserve,
        uint256 lpYpTotalSupply,
        uint256 yaReserve,
        uint256 lpYaTotalSupply,
        uint32 ltv,
        int64 apy
    )
        internal
        pure
        returns (
            uint128 yaMintedAmt,
            uint128 lpYaOutAmt,
            uint128 ypMintedAmt,
            uint128 lpYpOutAmt
        )
    {
        // yaAmt = cashAmt
        yaMintedAmt = cashAmt.toUint128();
        lpYaOutAmt = _calculateLpOut(yaReserve, yaMintedAmt, lpYaTotalSupply);

        // deal with case: apy < 0
        uint absoluteApy = int(apy).toUint256();
        if (apy >= 0) {
            ypMintedAmt = cashAmt
                .mulDiv(
                    ltv,
                    DECIMAL_BASE + (absoluteApy * daysTomaturity) / DAYS_IN_YEAR
                )
                .toUint128();
        } else {
            ypMintedAmt = cashAmt
                .mulDiv(
                    ltv,
                    DECIMAL_BASE - (absoluteApy * daysTomaturity) / DAYS_IN_YEAR
                )
                .toUint128();
        }
        lpYpOutAmt = _calculateLpOut(ypReserve, ypMintedAmt, lpYpTotalSupply);
    }

    function _calculateLpOut(
        uint256 tokenReserve,
        uint256 tokenIn,
        uint256 lpTotalSupply
    ) internal pure returns (uint128 lpOutAmt) {
        if (lpTotalSupply == 0) {
            lpOutAmt = tokenIn.toUint128();
        } else {
            // lpOutAmt = tokenIn/(tokenReserve/lpTotalSupply) = tokenIn*lpTotalSupply/tokenReserve
            lpOutAmt = tokenIn.mulDiv(lpTotalSupply, tokenReserve).toUint128();
        }
    }
}
