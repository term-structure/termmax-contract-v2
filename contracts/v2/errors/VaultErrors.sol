// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface VaultErrors {
    error MarketIsLaterThanMaturity();
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
}
