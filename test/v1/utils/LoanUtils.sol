// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Constants} from "contracts/v1/lib/Constants.sol";
import {DeployUtils} from "./DeployUtils.sol";

library LoanUtils {
    using SafeCast for uint256;
    using SafeCast for int256;

    function calcLtv(DeployUtils.Res memory res, uint256 debtAmt, uint256 collateralAmt)
        internal
        view
        returns (uint256 ltv)
    {
        (, int256 cPrice,,,) = res.collateralOracle.latestRoundData();
        (, int256 uPrice,,,) = res.debtOracle.latestRoundData();
        uint256 cpDecimals = 10 ** res.collateralOracle.decimals();
        uint256 upDecimals = 10 ** res.debtOracle.decimals();
        uint256 cDecimals = 10 ** res.collateral.decimals();
        uint256 uDecimals = 10 ** res.debt.decimals();
        uint256 debtValue = (debtAmt * uPrice.toUint256()) / uDecimals;
        uint256 collateralValue = (collateralAmt * cPrice.toUint256()) / (cpDecimals * cDecimals);
        if (collateralValue == 0) {
            return 2 ** 128 - 1;
        }
        ltv = (debtValue * Constants.DECIMAL_BASE) / (collateralValue * upDecimals);
    }

    function calcLiquidationResult(DeployUtils.Res memory res, uint256 debtAmt, uint256 collateralAmt, uint256 repayAmt)
        internal
        view
        returns (uint256 cToLiquidator, uint256 cToTreasurer, uint256 remainningC)
    {
        uint256 REWARD_TO_LIQUIDATOR = 0.05e8;
        uint256 REWARD_TO_PROTOCOL = 0.05e8;
        (, int256 cPrice,,,) = res.collateralOracle.latestRoundData();
        (, int256 uPrice,,,) = res.debtOracle.latestRoundData();
        uint256 cpDecimals = 10 ** res.collateralOracle.decimals();
        uint256 upDecimals = 10 ** res.debtOracle.decimals();
        uint256 cDecimals = 10 ** res.collateral.decimals();
        uint256 uDecimals = 10 ** res.debt.decimals();

        uint256 udPriceToCdPrice =
            (uPrice.toUint256() * cpDecimals * cpDecimals * 10 + cPrice.toUint256() - 1) / (cPrice.toUint256());

        uint256 cEqualRepayAmt = (repayAmt * udPriceToCdPrice * cDecimals) / (uDecimals * cpDecimals * upDecimals * 10);

        uint256 rewardToLiquidator = (cEqualRepayAmt * REWARD_TO_LIQUIDATOR) / Constants.DECIMAL_BASE;
        uint256 rewardToProtocol = (cEqualRepayAmt * REWARD_TO_PROTOCOL) / Constants.DECIMAL_BASE;

        uint256 removedCollateralAmt = cEqualRepayAmt + rewardToLiquidator + rewardToProtocol;
        if (removedCollateralAmt > (collateralAmt * repayAmt) / debtAmt) {
            removedCollateralAmt = (collateralAmt * repayAmt) / debtAmt;
        }
        if (cEqualRepayAmt + rewardToLiquidator >= removedCollateralAmt) {
            cToLiquidator = removedCollateralAmt;
        } else if (cEqualRepayAmt + rewardToLiquidator + rewardToProtocol >= removedCollateralAmt) {
            cToLiquidator = cEqualRepayAmt + rewardToLiquidator;
            cToTreasurer = removedCollateralAmt - cToLiquidator;
        } else {
            cToLiquidator = cEqualRepayAmt + rewardToLiquidator;
            cToTreasurer = rewardToProtocol;
        }
        remainningC = collateralAmt - removedCollateralAmt;
    }

    function fastMintGt(DeployUtils.Res memory res, address to, uint128 debtAmt, uint256 collateralAmt)
        internal
        returns (uint256 gtId, uint128 ftOutAmt)
    {
        res.collateral.mint(to, collateralAmt);
        res.collateral.approve(address(res.gt), collateralAmt);
        bytes memory collateralData = abi.encode(collateralAmt);

        (gtId, ftOutAmt) = res.market.issueFt(to, debtAmt, collateralData);
    }
}
