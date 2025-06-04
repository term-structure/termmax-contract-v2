// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TermMax Token Errors
 * @author Term Structure Labs
 */
interface TermMaxTokenErrors {
    /// @notice Error thrown when an invalid or unsupported token is used
    error InvalidToken();

    /**
     * @notice Error thrown when there's insufficient income available for a requested operation
     * @dev Used in income withdrawal scenarios where requested amount exceeds available balance
     * @param availableAmount The current available income amount
     * @param requestedAmount The amount that was requested but cannot be fulfilled
     */
    error InsufficientIncomeAmount(uint256 availableAmount, uint256 requestedAmount);

    /**
     * @notice Error thrown when an Aave withdrawal operation fails or returns unexpected amounts
     * @dev Indicates a mismatch between expected and actual amounts received from Aave protocol
     * @param aTokenAmount The amount of aTokens that were attempted to be withdrawn
     * @param recieivedAmount The actual amount received from the withdrawal (likely misspelled 'received')
     */
    error AaveWithdrawFailed(uint256 aTokenAmount, uint256 recieivedAmount);

    /// @notice Error thrown when trying to accept a change that has no pending value
    error NoPendingValue();

    /// @notice Error thrown when trying to accept a change before the timelock period has elapsed
    error TimelockNotElapsed();

    /// @notice Error thrown when attempting to submit a change that's already pending
    error AlreadyPending();

    /// @notice Error thrown when the implementation address is invalid
    error InvalidImplementation();
}
