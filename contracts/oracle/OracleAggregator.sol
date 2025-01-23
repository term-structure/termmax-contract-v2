// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AggregatorV3Interface, IOracle} from "./IOracle.sol";

contract OracleAggregator is IOracle, UUPSUpgradeable, Ownable2StepUpgradeable {
    /// @notice Oracles
    mapping(address => Oracle) public oracles;

    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    /**
     * @inheritdoc IOracle
     */
    function setOracle(address asset, Oracle memory oracle) external onlyOwner {
        if (
            asset == address(0) ||
            address(oracle.aggregator) == address(0) ||
            address(oracle.backupAggregator) == address(0)
        ) {
            revert InvalidAssetOrOracle();
        }
        oracles[asset] = oracle;
        emit UpdateOracle(asset, oracle.aggregator, oracle.backupAggregator, oracle.heartbeat);
    }

    /// @notice Remove oracle
    function removeOracle(address asset) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAssetOrOracle();
        }
        delete oracles[asset];
        emit UpdateOracle(asset, AggregatorV3Interface(address(0)), AggregatorV3Interface(address(0)), 0);
    }

    /**
     * @inheritdoc IOracle
     */
    function getPrice(address asset) external view override returns (uint256 price, uint8 decimals) {
        Oracle memory oracle = oracles[asset];
        (, int256 answer, , uint256 updatedAt, ) = oracle.aggregator.latestRoundData();
        if (oracle.heartbeat + updatedAt < block.timestamp || answer <= 0) {
            // switch backupAggregator
            (, answer, , updatedAt, ) = oracle.backupAggregator.latestRoundData();
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
