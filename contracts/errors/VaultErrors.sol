// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Vault Errors Interface
 * @notice Custom errors for the TermMax vault operations
 */
interface VaultErrors {
    error InvalidImplementation();
    /**
     * @notice Error thrown when attempting to interact with a vault without its proxy
     */
    error OnlyProxy();

    /**
     * @notice Error thrown when attempting to interact with a non-whitelisted market
     */
    error MarketNotWhitelisted();

    /**
     * @notice Error thrown when trying to deal with bad debt that doesn't exist
     * @param collateral The address of the collateral token
     */
    error NoBadDebt(address collateral);

    /**
     * @notice Error thrown when attempting to withdraw more funds than available
     * @param maxWithdraw The maximum amount that can be withdrawn
     * @param expectedWithdraw The amount attempted to withdraw
     */
    error InsufficientFunds(uint256 maxWithdraw, uint256 expectedWithdraw);

    /**
     * @notice Error thrown when the locked FT amount exceeds the total FT
     */
    error LockedFtGreaterThanTotalFt();

    /**
     * @notice Error thrown when attempting to set a performance fee rate beyond the maximum allowed
     */
    error PerformanceFeeRateExceeded();

    /**
     * @notice Error thrown when there's an asset mismatch in an operation
     */
    error InconsistentAsset();

    /**
     * @notice Error thrown when trying to accept a change that has no pending value
     */
    error NoPendingValue();

    /**
     * @notice Error thrown when trying to accept a change before the timelock period has elapsed
     */
    error TimelockNotElapsed();

    /**
     * @notice Error thrown when attempting to set a timelock period above the maximum
     */
    error AboveMaxTimelock();

    /**
     * @notice Error thrown when attempting to set a timelock period below the minimum
     */
    error BelowMinTimelock();

    /**
     * @notice Error thrown when attempting to set a value that's already set
     */
    error AlreadySet();

    /**
     * @notice Error thrown when attempting to submit a change that's already pending
     */
    error AlreadyPending();

    /**
     * @notice Error thrown when attempting to exceed the maximum queue length
     */
    error MaxQueueLengthExceeded();

    /**
     * @notice Error thrown when a non-curator attempts to perform a curator-only action
     */
    error NotCuratorRole();

    /**
     * @notice Error thrown when a non-allocator attempts to perform an allocator-only action
     */
    error NotAllocatorRole();

    /**
     * @notice Error thrown when a non-guardian attempts to perform a guardian-only action
     */
    error NotGuardianRole();

    /**
     * @notice Error thrown when attempting to set the capacity to zero
     */
    error CapacityCannotSetToZero();

    /**
     * @notice Error thrown when attempting to set capacity below the currently used amount
     */
    error CapacityCannotLessThanUsed();

    /**
     * @notice Error thrown when an unauthorized order attempts to interact with the vault
     * @param orderAddress The address of the unauthorized order
     */
    error UnauthorizedOrder(address orderAddress);

    /**
     * @notice Error thrown when the supply queue length doesn't match the expected length
     */
    error SupplyQueueLengthMismatch();

    /**
     * @notice Error thrown when the withdraw queue length doesn't match the expected length
     */
    error WithdrawQueueLengthMismatch();

    /**
     * @notice Error thrown when attempting to add a duplicate order to a queue
     * @param orderAddress The address of the duplicate order
     */
    error DuplicateOrder(address orderAddress);

    /**
     * @notice Error thrown when an order has negative interest
     */
    error OrderHasNegativeInterest();
}
