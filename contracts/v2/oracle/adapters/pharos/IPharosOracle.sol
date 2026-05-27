// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPharosOracle
 * @notice Interface for Pharos oracle price feeds
 */
interface IPharosOracle {
    /// @notice Get the number of decimals for the price feed
    function decimals() external view returns (uint8);

    /// @notice Get the latest answer
    function latestAnswer() external view returns (int256);

    /// @notice Get the latest timestamp
    function latestTimestamp() external view returns (uint256);
}
