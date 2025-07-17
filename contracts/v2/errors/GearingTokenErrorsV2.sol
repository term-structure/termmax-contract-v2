// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface GearingTokenErrorsV2 {
    /// @notice Error for Liquidation LTV too excess 100%
    error InvalidLiquidationLtv();
    /// @notice Error for merge empty Gearing Token id array
    error GtIdArrayIsEmpty();
}
