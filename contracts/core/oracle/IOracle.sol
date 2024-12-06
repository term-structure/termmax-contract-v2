// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title IOracle
 * @author Term Structure Labs
 */
interface IOracle {
    struct Oracle {
        AggregatorV3Interface aggregator;
        AggregatorV3Interface backupAggregator;
        uint32 heartbeat;
    }
    /// @notice Error thrown when the oracle is not working
    error OracleIsNotWorking(address asset);

    /// @notice Event emitted when the oracle of asset is updated
    /// @param asset The address of the asset
    /// @param aggregator The address of the aggregator
    /// @param backupAggregator The address of the backup aggregator
    /// @param heartbeat The heartbeat of the oracle
    event UpdateOracle(
    address indexed asset,
    AggregatorV3Interface indexed aggregator,
    AggregatorV3Interface indexed backupAggregator,
    uint32 heartbeat);

    /// @notice Get the price of an asset
    function getPrice(address asset) external view returns (uint256 price, uint8 decimals);

    /// @notice Set oracle
    function setOracle(address asset, Oracle memory oracle) external;
}