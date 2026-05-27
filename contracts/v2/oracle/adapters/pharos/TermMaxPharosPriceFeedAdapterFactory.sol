// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxPharosPriceFeedAdapter} from "./TermMaxPharosPriceFeedAdapter.sol";

/**
 * @title TermMaxPharosPriceFeedAdapterFactory
 * @notice Factory contract for deploying TermMaxPharosPriceFeedAdapter instances
 */
contract TermMaxPharosPriceFeedAdapterFactory {
    /// @notice Emitted when a new adapter is deployed
    event AdapterDeployed(address indexed pharosOracle, address indexed asset, address indexed adapter);

    /**
     * @notice Deploy a new TermMaxPharosPriceFeedAdapter for a given Pharos oracle
     * @param pharosOracle The Pharos oracle contract address
     * @param asset The asset whose price is provided by the oracle
     * @return adapter The address of the newly deployed adapter
     */
    function deployAdapter(address pharosOracle, address asset) external returns (address adapter) {
        require(pharosOracle != address(0) && asset != address(0), "Pharos oracle and asset addresses cannot be zero");
        adapter = address(new TermMaxPharosPriceFeedAdapter(pharosOracle, asset));
        emit AdapterDeployed(pharosOracle, asset, adapter);
    }
}
