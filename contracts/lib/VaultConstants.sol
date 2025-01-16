// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library VaultConstants {
    /// @dev The maximum delay of a timelock.
    uint256 internal constant MAX_TIMELOCK = 2 weeks;

    /// @dev The minimum delay of a timelock post initialization.
    uint256 internal constant POST_INITIALIZATION_MIN_TIMELOCK = 1 days;

    /// @dev The maximum number of markets in the supply/withdraw queue.
    uint256 internal constant MAX_QUEUE_LENGTH = 30;

    /// @dev The maximum fee the vault can have (50%).
    uint256 internal constant MAX_FEE = 0.5e18;

    /// @dev The maximum term the vault can have.
    uint256 internal constant MAX_TERM = 365 days;

    /// @dev The maximum performance fee rate the vault can have.
    uint256 internal constant MAX_PERFORMANCE_FEE_RATE = 0.5e8;
}
