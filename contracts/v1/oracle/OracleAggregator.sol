// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AggregatorV3Interface, IOracle} from "./IOracle.sol";

contract OracleAggregator is IOracle, Ownable2Step {
    uint256 internal immutable _timeLock;

    struct PendingOracle {
        Oracle oracle;
        uint64 validAt;
    }

    /// @notice Error thrown when the asset or oracle address is invalid
    error InvalidAssetOrOracle();

    /**
     * @notice Error thrown when attempting to set a value that's already set
     */
    error AlreadySet();

    /**
     * @notice Error thrown when attempting to submit a change that's already pending
     */
    error AlreadyPending();

    /**
     * @notice Error thrown when trying to accept a change that has no pending value
     */
    error NoPendingValue();

    /**
     * @notice Error thrown when trying to accept a change before the timelock period has elapsed
     */
    error TimelockNotElapsed();

    /// @notice Event emitted when the oracle of asset is updated
    /// @param asset The address of the asset
    /// @param aggregator The address of the aggregator
    /// @param backupAggregator The address of the backup aggregator
    /// @param heartbeat The heartbeat of the oracle
    event UpdateOracle(
        address indexed asset,
        AggregatorV3Interface indexed aggregator,
        AggregatorV3Interface indexed backupAggregator,
        uint32 heartbeat
    );

    event SubmitPendingOracle(
        address indexed asset,
        AggregatorV3Interface indexed aggregator,
        AggregatorV3Interface indexed backupAggregator,
        uint32 heartbeat,
        uint64 validAt
    );

    event RevokePendingOracle(address indexed asset);

    /// @notice Oracles
    mapping(address => Oracle) public oracles;

    mapping(address => PendingOracle) public pendingOracles;

    constructor(address _owner, uint256 timeLock) Ownable(_owner) {
        _timeLock = timeLock;
    }

    function submitPendingOracle(address asset, Oracle memory oracle) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAssetOrOracle();
        }
        if (address(oracle.aggregator) == address(0) && address(oracle.backupAggregator) == address(0)) {
            delete oracles[asset];
            emit UpdateOracle(asset, AggregatorV3Interface(address(0)), AggregatorV3Interface(address(0)), 0);
            return;
        }
        pendingOracles[asset].oracle = oracle;
        uint64 validAt = uint64(block.timestamp + _timeLock);
        pendingOracles[asset].validAt = validAt;
        emit SubmitPendingOracle(asset, oracle.aggregator, oracle.backupAggregator, oracle.heartbeat, validAt);
    }

    function acceptPendingOracle(address asset) external {
        if (pendingOracles[asset].validAt == 0) {
            revert NoPendingValue();
        }
        if (block.timestamp < pendingOracles[asset].validAt) {
            revert TimelockNotElapsed();
        }
        Oracle memory oracle = pendingOracles[asset].oracle;
        oracles[asset] = oracle;
        delete pendingOracles[asset];
        emit UpdateOracle(asset, oracle.aggregator, oracle.backupAggregator, oracle.heartbeat);
    }

    /**
     * @inheritdoc IOracle
     */
    function getPrice(address asset) external view override returns (uint256 price, uint8 decimals) {
        Oracle memory oracle = oracles[asset];
        (, int256 answer,, uint256 updatedAt,) = oracle.aggregator.latestRoundData();
        if (oracle.heartbeat + updatedAt < block.timestamp || answer <= 0) {
            // switch backupAggregator
            (, answer,, updatedAt,) = oracle.backupAggregator.latestRoundData();
            if (oracle.heartbeat + updatedAt < block.timestamp || answer <= 0) {
                revert OracleIsNotWorking(asset);
            }
            decimals = oracle.backupAggregator.decimals();
        } else {
            decimals = oracle.aggregator.decimals();
        }
        price = uint256(answer);
    }
}
