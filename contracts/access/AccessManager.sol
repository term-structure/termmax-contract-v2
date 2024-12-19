// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITermMaxMarket} from "contracts/core/ITermMaxMarket.sol";
import {ITermMaxFactory} from "contracts/core/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {IOracle} from "contracts/core/oracle/IOracle.sol";
import {MarketConfig} from "contracts/core/storage/TermMaxStorage.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

/**
 * @title TermMax Access Manager
 * @author Term Structure Labs
 */
contract AccessManager is AccessControlUpgradeable, UUPSUpgradeable {
    /// @notice Role to manage switch
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role to manage configuration items
    bytes32 public constant CURATOR_ROLE = keccak256("CURATOR_ROLE");

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CURATOR_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
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
        ITermMaxFactory.MarketDeployParams calldata deployParams
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        market = factory.createMarket(deployParams);
    }

    /// @notice Deploy a new market
    function createMarketAndWhitelist(
        ITermMaxRouter router,
        ITermMaxFactory factory,
        ITermMaxFactory.MarketDeployParams calldata deployParams
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address market) {
        market = factory.createMarket(deployParams);
        router.setMarketWhitelist(market, true);
    }

    /// @notice Transfer ownable contract's ownership
    function transferOwnership(
        address entity,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IOwnable(entity).transferOwnership(to);
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
    function setOracle(IOracle aggregator, address asset, IOracle.Oracle memory oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
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
    ) external onlyRole(CURATOR_ROLE) {
        market.updateMarketConfig(newConfig);
    }

    /// @notice Set the provider's white list
    function setProvider(ITermMaxMarket market, address provider) external onlyRole(CURATOR_ROLE) {
        market.setProvider(provider);
    }

    // /// @notice Set the configuration of Gearing Token
    // function updateGtConfig(ITermMaxMarket market, bytes memory configData) external onlyRole(CURATOR_ROLE){
    //     market.updateGtConfig(configData);
    // }

    /// @notice Set the switch for this market
    function setSwitchOfMarket(
        ITermMaxMarket market,
        bool state
    ) external onlyRole(PAUSER_ROLE) {
        if (state) {
            market.unpause();
        } else {
            market.pause();
        }
    }

    /// @notice Set the switch for Router
    function setSwitchOfRouter(
        ITermMaxRouter router,
        bool state
    ) external onlyRole(PAUSER_ROLE) {
        router.togglePause(state);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
