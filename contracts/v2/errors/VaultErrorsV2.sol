// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Vault Errors V2
 * @author Term Structure Labs
 */
interface VaultErrorsV2 {
    /// @notice Error thrown when the parameters of updating orders are invalid
    error ArrayLengthMismatch();
    /// @notice Error thrown when dealing unexpected collateral
    error CollateralIsAsset();
    /// @notice Error thrown when an invalid or unsupported functions is called
    error UseVaultInitialParamsV2();
    /// @notice Error thrown when an invalid or unsupported functions is called
    error SupplyQueueNoLongerSupported();
    /// @notice Error thrown when an invalid or unsupported functions is called
    error WithdrawalQueueNoLongerSupported();
    /// @notice Error thrown when an invalid or unsupported functions is called
    error UseApyInsteadOfApr();
    /// @notice Error thrown when the APY is too low
    error ApyTooLow(uint256 apy, uint256 minApy);
    /// @notice Error thrown when the idle fund rate is too low
    error IdleFundRateTooLow(uint256 idleFundRate, uint256 minIdleFundRate);
}
