// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Roles
/// @notice Defines role constants for access control in the TermMax protocol
abstract contract Roles {
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
    /// @notice Role to manage whitelist
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    /// @notice Role to upgrade contracts
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Role to configure TermMax market factory
    bytes32 public constant TERMMAX_MARKET_FACTORY_ROLE = keccak256("TERMMAX_MARKET_FACTORY_ROLE");
    /// @notice Role to configure TermMax 4626 pools
    bytes32 public constant TERMMAX_4626_FACTORY_ROLE = keccak256("TERMMAX_4626_FACTORY_ROLE");
    /// @notice Role to deploy pools
    bytes32 public constant POOL_DEPLOYER_ROLE = keccak256("POOL_DEPLOYER_ROLE");
    /// @notice Role to deploy vaults
    bytes32 public constant VAULT_DEPLOYER_ROLE = keccak256("VAULT_DEPLOYER_ROLE");
    /// @notice Role to update stable ERC4626 buffer config and add reserves
    bytes32 public constant STABLE_ERC4626_BUFFER_ROLE = keccak256("STABLE_ERC4626_BUFFER_ROLE");
    /// @notice Role to withdraw stable ERC4626 income assets
    bytes32 public constant STABLE_ERC4626_INCOME_WITHDRAW_ROLE = keccak256("STABLE_ERC4626_INCOME_WITHDRAW_ROLE");
}
