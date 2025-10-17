// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface GearingTokenErrorsV2 {
    /// @notice Error for Liquidation LTV too excess 100%
    error InvalidLiquidationLtv();
    /// @notice Error for merge empty Gearing Token id array
    error GtIdArrayIsEmpty();
    /// @notice Error for Gearing Token is expired
    error GtIsExpired();
    /// @notice Error for Gearing Token id is duplicate when merging
    error DuplicateIdInMerge(uint256 id);

    /// @notice The operation failed because the collateral capacity is exceeded
    error CollateralCapacityExceeded();
    /// @notice The operation failed because the collateral data is invalid
    error InvalidCollateralData();
    /// @notice The operation failed because cannot remove collateral with debt
    error CannotRemoveCollateralWithDebt();
    /// @notice The operation failed because gearing token do not support liquidation
    error CannotAugmentDebtOnOnlyDeliveryGt();
    /// @notice The operation failed because gearing token do not support liquidation
    error OnlyFullRepaySupported();
}
