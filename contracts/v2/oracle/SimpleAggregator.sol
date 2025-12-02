// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./IOracleV2.sol";

/**
 * @title SimpleAggregator
 * @author Term Structure Labs
 * @notice The SimpleAggregator for constant token pairs
 */
contract SimpleAggregator is IOracleV2 {
    mapping(address => AggregatorV3Interface) public oracles;

    constructor(address[2] memory assets, AggregatorV3Interface[2] memory _oracles) {
        /// @notice Make sure the oracles are constant aggregators
        oracles[assets[0]] = _oracles[0];
        oracles[assets[1]] = _oracles[1];
    }

    function getPrice(address asset) external view returns (uint256 price, uint8 decimals) {
        /// @dev Their were no checks on the oracle since they are constant price feeds
        AggregatorV3Interface oracle = oracles[asset];
        (, int256 answer,,,) = oracle.latestRoundData();
        price = uint256(answer);
        decimals = oracle.decimals();
    }

    function submitPendingOracle(address asset, Oracle memory oracle) external {}

    function acceptPendingOracle(address asset) external {}

    function revokePendingOracle(address asset) external {}
}
