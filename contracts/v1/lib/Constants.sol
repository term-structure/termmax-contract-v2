// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title The general constants of TermMax
 * @author Term Structure Labs
 */
library Constants {
    /// @notice The base decimals of ratio
    uint256 constant DECIMAL_BASE = 1e8;
    /// @notice The square of the base decimals
    uint256 constant DECIMAL_BASE_SQ = 1e16;
    /// @notice The days of one year
    uint256 constant DAYS_IN_YEAR = 365;
    /// @notice The seconds of one day
    uint256 constant SECONDS_IN_DAY = 1 days;
    /// @notice The window time left for the liquidation bot after the market expires
    uint256 constant LIQUIDATION_WINDOW = 2 hours;
    /// @notice The limit of fee ratio
    uint32 constant MAX_FEE_RATIO = 0.2e8;
}
