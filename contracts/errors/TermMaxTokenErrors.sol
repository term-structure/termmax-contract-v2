// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface TermMaxTokenErrors {
    error InvalidToken();
    error InsufficientIncomeAmount(uint256 availableAmount, uint256 requestedAmount);
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
