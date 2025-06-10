// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Vault Errors V2
 * @author Term Structure Labs
 */
interface VaultErrorsV2 {
    /// @notice Error thrown when an invalid or unsupported functions is called
    error SupplyQueueNoLongerSupported();
    /// @notice Error thrown when an invalid or unsupported functions is called
    error WithdrawalQueueNoLongerSupported();
    /// @notice Error thrown when an invalid or unsupported functions is called
    error UseApyInsteadOfApr();
}
