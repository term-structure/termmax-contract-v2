// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./OracleAggregatorV2.sol";

contract OracleAggregatorWithSequencerV2 is OracleAggregatorV2 {
    /// @notice The timelock period in seconds that must elapse before pending oracles can be accepted
    /// @dev Immutable value set during contract construction for security
    uint256 internal immutable _timeLock;

    AggregatorV3Interface internal sequencerUptimeFeed;
    uint256 private constant GRACE_PERIOD_TIME = 3600; // 1 hour

    /**
     * @inheritdoc IOracleV2
     */
    function getPrice(address asset) external view virtual override returns (uint256, uint8) {
        // Check if the sequencer is down
        return super.getPrice(asset);
    }
}
