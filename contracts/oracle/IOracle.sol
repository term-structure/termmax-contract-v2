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

    /// @notice Get the price of an asset
    function getPrice(address asset) external view returns (uint256 price, uint8 decimals);

    function submitPendingOracle(address asset, Oracle memory oracle) external;

    function acceptPendingOracle(address asset) external;
}
