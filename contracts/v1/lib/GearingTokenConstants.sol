// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title The constants of GearingToken
 * @author Term Structure Labs
 */
library GearingTokenConstants {
    /// @notice The percentage of repay amount to liquidator while do liquidate, decimals 1e8
    uint256 constant REWARD_TO_LIQUIDATOR = 0.05e8;
    /// @notice The percentage of repay amount to protocol while do liquidate, decimals 1e8
    uint256 constant REWARD_TO_PROTOCOL = 0.05e8;
    /// @notice Semi-liquidation threshold: if the value of the collateral reaches this value,
    ///         only partial liquidation can be performed, decimals 1e8.
    uint256 constant HALF_LIQUIDATION_THRESHOLD = 10000e8;
}
