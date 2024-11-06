// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DeployUtils, Constants} from "./DeployUtils.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library LoanUtils {
    using SafeCast for uint256;
    using SafeCast for int256;

    function calcLtv(
        DeployUtils.Res memory res,
        uint debtAmt,
        uint collateralAmt
    ) internal view returns (uint256 ltv) {
        (, int256 cPrice, , , ) = res.collateralOracle.latestRoundData();
        (, int256 uPrice, , , ) = res.underlyingOracle.latestRoundData();
        uint cpDecimals = 10 ** res.collateralOracle.decimals();
        uint upDecimals = 10 ** res.underlyingOracle.decimals();
        uint cDecimals = 10 ** res.collateral.decimals();
        uint uDecimals = 10 ** res.underlying.decimals();
        uint debtValue = (debtAmt * uPrice.toUint256()) /
            (upDecimals * uDecimals);
        uint collateralValue = (collateralAmt * cPrice.toUint256()) /
            (cpDecimals * cDecimals);
        ltv = (debtValue * Constants.DECIMAL_BASE) / collateralValue;
    }
}
