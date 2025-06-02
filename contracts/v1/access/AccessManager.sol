// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxFactory} from "../factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "../router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {IOracle} from "../oracle/IOracle.sol";
import {ITermMaxVault} from "../vault/ITermMaxVault.sol";
import {MarketConfig, FeeConfig, MarketInitialParams} from "../storage/TermMaxStorage.sol";

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
    error CannotRevokeDefaultAdminRole();

    /// @notice Role to manage switch
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Role to manage configuration items
    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    /// @notice Role to manage vault
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    /// @notice Role to manage oracle
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    /// @notice Role to manage market
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Set GT implementation to the factory
    function setGtImplement(ITermMaxFactory factory, string memory gtImplementName, address gtImplement)
        external
        onlyRole(MARKET_ROLE)
    {
        factory.setGtImplement(gtImplementName, gtImplement);
    }

    /// @notice Deploy a new market
    function createMarket(
        ITermMaxFactory factory,
        bytes32 gtKey,
        MarketInitialParams calldata deployParams,
        uint256 salt
    ) external onlyRole(MARKET_ROLE) returns (address market) {
        market = factory.createMarket(gtKey, deployParams, salt);
    }

    /// @notice Transfer ownable contract's ownership
    function transferOwnership(IOwnable entity, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        entity.transferOwnership(to);
    }

    function acceptOwnership(IOwnable entity) external onlyRole(DEFAULT_ADMIN_ROLE) {
        entity.acceptOwnership();
    }

    /// @notice Upgrade the target contract using UUPS
    function upgradeSubContract(UUPSUpgradeable proxy, address newImplementation, bytes memory data)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        proxy.upgradeToAndCall(newImplementation, data);
    }

    /// @notice Set the adapter whitelist for router
    function setAdapterWhitelist(ITermMaxRouter router, address adapter, bool isWhitelist)
        external
        onlyRole(MARKET_ROLE)
    {
        router.setAdapterWhitelist(adapter, isWhitelist);
    }

    function submitPendingOracle(IOracle aggregator, address asset, IOracle.Oracle memory oracle)
        external
        onlyRole(ORACLE_ROLE)
    {
        aggregator.submitPendingOracle(asset, oracle);
    }

    function acceptPendingOracle(IOracle aggregator, address asset) external onlyRole(ORACLE_ROLE) {
        aggregator.acceptPendingOracle(asset);
    }

    /// @notice Update the market configuration
    function updateMarketConfig(ITermMaxMarket market, MarketConfig calldata newConfig)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        market.updateMarketConfig(newConfig);
    }

    /// @notice Set the configuration of Gearing Token
    function updateGtConfig(ITermMaxMarket market, bytes memory configData) external onlyRole(CONFIGURATOR_ROLE) {
        market.updateGtConfig(configData);
    }

    /// @notice Set the fee rate of an order
    function updateOrderFeeRate(ITermMaxMarket market, ITermMaxOrder order, FeeConfig memory feeConfig)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        market.updateOrderFeeRate(order, feeConfig);
    }

    /// @notice Set the switch of an entity
    function setSwitch(IPausable entity, bool state) external onlyRole(PAUSER_ROLE) {
        if (state) {
            entity.unpause();
        } else {
            entity.pause();
        }
    }

    function submitVaultGuardian(ITermMaxVault vault, address newGuardian) external onlyRole(VAULT_ROLE) {
        vault.submitGuardian(newGuardian);
    }

    /// @notice Revoke a pending guardian for the vault
    function revokeVaultPendingGuardian(ITermMaxVault vault) external onlyRole(VAULT_ROLE) {
        vault.revokePendingGuardian();
    }

    /// @notice Revoke a pending timelock for the vault
    function revokeVaultPendingTimelock(ITermMaxVault vault) external onlyRole(VAULT_ROLE) {
        vault.revokePendingTimelock();
    }

    /// @notice Revoke a pending market for the vault
    function revokeVaultPendingMarket(ITermMaxVault vault, address market) external onlyRole(VAULT_ROLE) {
        vault.revokePendingMarket(market);
    }

    /// @notice Set the curator for the vault, only admin role
    function setCuratorForVault(ITermMaxVault vault, address newCurator) external onlyRole(VAULT_ROLE) {
        vault.setCurator(newCurator);
    }

    /// @notice Set the allocator for the vault
    function setIsAllocatorForVault(ITermMaxVault vault, address allocator, bool isAllocator)
        external
        onlyRole(VAULT_ROLE)
    {
        vault.setIsAllocator(allocator, isAllocator);
    }

    /// @notice Revoke role
    /// @dev Can't revoke your own role
    function revokeRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        if (msg.sender == account) {
            revert AccessControlBadConfirmation();
        }

        _revokeRole(role, account);
    }

    /// @notice Revoke role
    /// @dev Can't revoke default admin role
    function renounceRole(bytes32 role, address callerConfirmation) public override {
        if (role == DEFAULT_ADMIN_ROLE) {
            revert CannotRevokeDefaultAdminRole();
        }
        _revokeRole(role, callerConfirmation);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
