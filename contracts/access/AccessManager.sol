// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {MarketConfig, FeeConfig, MarketInitialParams} from "contracts/storage/TermMaxStorage.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;

    function acceptOwnership() external;
}

interface IPausable {
    function pause() external;

    function unpause() external;
}

/**
 * @title TermMax Access Manager
 * @author Term Structure Labs
 */
contract AccessManager is AccessControlUpgradeable, UUPSUpgradeable {
    /// @notice Role to manage switch
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role to manage configuration items
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Set GT implementation to the factory
    function setGtImplement(
        ITermMaxFactory factory,
        string memory gtImplementName,
        address gtImplement
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        factory.setGtImplement(gtImplementName, gtImplement);
    }

    /// @notice Deploy a new market
    function createMarket(
        ITermMaxFactory factory,
        bytes32 gtKey,
        MarketInitialParams calldata deployParams,
        uint256 salt
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        market = factory.createMarket(gtKey, deployParams, salt);
    }

    /// @notice Deploy a new market and whitelist it
    function createMarketAndWhitelist(
        ITermMaxRouter router,
        ITermMaxFactory factory,
        bytes32 gtKey,
        MarketInitialParams calldata deployParams,
        uint256 salt
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        market = factory.createMarket(gtKey, deployParams, salt);
        router.setMarketWhitelist(market, true);
    }

    /// @notice Transfer ownable contract's ownership
    function transferOwnership(IOwnable entity, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        entity.transferOwnership(to);
    }

    function accessOwnership(IOwnable entity) external onlyRole(DEFAULT_ADMIN_ROLE) {
        entity.acceptOwnership();
    }

    /// @notice Upgrade the target contract using UUPS
    function upgradeSubContract(
        UUPSUpgradeable proxy,
        address newImplementation,
        bytes memory data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proxy.upgradeToAndCall(newImplementation, data);
    }

    /// @notice Set the market whitelist for router
    function setMarketWhitelist(
        ITermMaxRouter router,
        address market,
        bool isWhitelist
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        router.setMarketWhitelist(market, isWhitelist);
    }

    /// @notice Set the adapter whitelist for router
    function setAdapterWhitelist(
        ITermMaxRouter router,
        address adapter,
        bool isWhitelist
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        router.setAdapterWhitelist(adapter, isWhitelist);
    }

    /// @notice Set the oracle
    function setOracle(
        IOracle aggregator,
        address asset,
        IOracle.Oracle memory oracle
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aggregator.setOracle(asset, oracle);
    }

    /// @notice Remove the oracle
    function removeOracle(IOracle aggregator, address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aggregator.removeOracle(asset);
    }

    /// @notice Update the market configuration
    function updateMarketConfig(
        ITermMaxMarket market,
        MarketConfig calldata newConfig
    ) external onlyRole(CONFIGURATOR_ROLE) {
        market.updateMarketConfig(newConfig);
    }

    /// @notice Set the configuration of Gearing Token
    function updateGtConfig(ITermMaxMarket market, bytes memory configData) external onlyRole(CONFIGURATOR_ROLE) {
        market.updateGtConfig(configData);
    }

    /// @notice Set the fee rate of an order
    function setOrderFeeRate(ITermMaxOrder order, FeeConfig memory feeConfig) external onlyRole(CONFIGURATOR_ROLE) {
        order.updateFeeConfig(feeConfig);
    }

    /// @notice Set the switch of an entity
    function setSwitch(IPausable entity, bool state) external onlyRole(PAUSER_ROLE) {
        if (state) {
            entity.unpause();
        } else {
            entity.pause();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
