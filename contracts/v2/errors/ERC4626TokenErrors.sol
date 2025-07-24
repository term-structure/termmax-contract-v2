// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ERC4626TokenErrors
 * @author Term Structure Labs
 * @notice Contains error definitions for the ERC4626 token contract
 */
interface ERC4626TokenErrors {
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
}
