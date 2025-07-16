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
    /// @notice Error thrown when initializing the vault using V1 initializing function
    error UseVaultInitialParamsV2();
    /// @notice Error thrown when calling functions about supply queue
    error SupplyQueueNoLongerSupported();
    /// @notice Error thrown when calling functions about withdrawal queue
    error WithdrawalQueueNoLongerSupported();
    /// @notice Error thrown when calling apr function
    error UseApyInsteadOfApr();
    /// @notice Error thrown when the APY is too low
    error ApyTooLow(uint256 apy, uint256 minApy);
    /// @notice Error thrown when the market is not whitelisted
    error MarketNotWhitelisted(address market);
}
