// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./OracleAggregatorV2.sol";

contract OracleAggregatorWithSequencerV2 is OracleAggregatorV2 {
    event SequencerUptimeFeedUpdated(address indexed sequencerUptimeFeed, uint256 gracePeriodTime);
    /// @notice Error thrown when the sequencer is down

    error SequencerIsDown();

    /// @notice The address of the sequencer uptime feed aggregator
    AggregatorV3Interface internal sequencerUptimeFeed;
    /// @notice The grace period time in seconds for the sequencer uptime feed
    uint256 private gracePeriodTime;

    constructor(address owner, uint256 timeLock, address _sequencerUptimeFeed, uint256 _gracePeriodTime) OracleAggregatorV2(owner, timeLock)
    {
        setSequencerUptimeFeedAndGracePeriod(_sequencerUptimeFeed, _gracePeriodTime);
    }

    function setSequencerUptimeFeedAndGracePeriod(address _sequencerUptimeFeed, uint256 _gracePeriodTime) public onlyOwner {
        sequencerUptimeFeed = AggregatorV3Interface(_sequencerUptimeFeed);
        gracePeriodTime = _gracePeriodTime;

        emit SequencerUptimeFeedUpdated(_sequencerUptimeFeed, _gracePeriodTime);
    }

    function getPrice(address asset) public view virtual override returns (uint256, uint8) {
        // Check if the sequencer is down
        require(_isSequencerUp(), SequencerIsDown());
        return super.getPrice(asset);
    }

    function _isSequencerUp() internal view returns (bool) {
        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        bool isGracePeriodOver = block.timestamp - startedAt > gracePeriodTime;

        return isSequencerUp && isGracePeriodOver;
    }
}
