// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface VaultErrors {
    error NoBadDebt(address collateral);
    error InsufficientFunds(uint256 maxWithdraw, uint256 expectedWithdraw);
    error MarketIsLaterThanMaxTerm();
    error LockedFtGreaterThanTotalFt();

    error InconsistentAsset();
    error NoPendingValue();
    error TimelockNotElapsed();
    error AboveMaxTimelock();
    error BelowMinTimelock();
    error AlreadySet();
    error AlreadyPending();
    error MaxQueueLengthExceeded();
    error NotCuratorRole();
    error NotAllocatorRole();
    error NotGuardianRole();
    error CapacityCannotSetToZero();
    error CapacityCannotLessThanUsed();
    error UnauthorizedOrder(address orderAddress);
    error SupplyQueueLengthMismatch();
    error WithdrawQueueLengthMismatch();
    error DuplicateOrder(address orderAddress);
}
