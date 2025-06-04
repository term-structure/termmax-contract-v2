// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Market Errors Interface
 * @notice Custom errors for the TermMax market operations
 */
interface MarketErrors {
    /**
     * @notice Error thrown when a fee rate is set higher than the maximum allowed
     */
    error FeeTooHigh();

    /**
     * @notice Error thrown when the maturity date is invalid
     * @dev This could be due to maturity being in the past or too far in the future
     */
    error InvalidMaturity();

    /**
     * @notice Error thrown when trying to use the same token as both collateral and underlying
     * @dev Collateral and underlying must be different tokens for market safety
     */
    error CollateralCanNotEqualUnderlyinng();

    /**
     * @notice Error thrown when trying to interact with a market before its trading period begins
     */
    error TermIsNotOpen();

    /**
     * @notice Error thrown when attempting to redeem before the final liquidation deadline
     * @param liquidationDeadline The timestamp after which redemption is allowed
     */
    error CanNotRedeemBeforeFinalLiquidationDeadline(uint256 liquidationDeadline);
}
