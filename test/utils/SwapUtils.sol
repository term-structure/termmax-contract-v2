// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DeployUtils, Constants} from "./DeployUtils.sol";

library SwapUtils {
    using SafeCast for uint256;
    using SafeCast for int256;

    function getPrice(
        DeployUtils.Res memory res
    ) internal view returns (uint256 pFt, uint256 pYt) {
        int apr = res.market.config().apr;
        uint dtm = daysToMaturity(res.market.config().maturity);
        if (apr > 0) {
            pFt =
                Constants.DECIMAL_BASE_SQ /
                (Constants.DECIMAL_BASE +
                    (uint(apr) * dtm) /
                    Constants.DAYS_IN_YEAR);
        } else {
            pFt =
                Constants.DECIMAL_BASE_SQ /
                (Constants.DECIMAL_BASE -
                    (uint(-apr) * dtm) /
                    Constants.DAYS_IN_YEAR);
        }
        pYt =
            Constants.DECIMAL_BASE -
            (pFt * res.market.config().initialLtv) /
            Constants.DECIMAL_BASE;
    }

    function daysToMaturity(uint maturity) internal view returns (uint256) {
        return
            (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) /
            Constants.SECONDS_IN_DAY;
    }
}
