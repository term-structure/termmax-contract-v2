// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DeployUtils, Constants} from "./DeployUtils.sol";

library SwapUtils {
    using SafeCast for uint256;
    using SafeCast for int256;

    function getPrice(DeployUtils.Res memory res) internal view returns (uint256 pFt, uint256 pXt) {
        (uint lendApr_, uint borrowApr_) = res.market.apr();

        uint dtm = daysToMaturity(res.tokenPair.config().maturity);
        pFt = Constants.DECIMAL_BASE_SQ / (Constants.DECIMAL_BASE + (lendApr_ * dtm) / Constants.DAYS_IN_YEAR);
        pXt = Constants.DECIMAL_BASE - pFt / Constants.DECIMAL_BASE;
    }

    function daysToMaturity(uint maturity) internal view returns (uint256) {
        return (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }
}
