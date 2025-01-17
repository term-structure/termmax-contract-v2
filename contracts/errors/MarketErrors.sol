// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface MarketErrors {
    error FeeTooHigh();
    /// @notice Error for invalid maturity
    error InvalidMaturity();
    /// @notice Error for the collateral and underlying are the same token
    error CollateralCanNotEqualUnderlyinng();
    /// @notice Error for it is not the opening trading day yet
    error TermIsNotOpen();
    /// @notice Error for redeeming before the liquidation window
    error CanNotRedeemBeforeFinalLiquidationDeadline(uint256 liquidationDeadline);
}
