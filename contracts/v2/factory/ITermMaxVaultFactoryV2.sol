// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultInitialParamsV2} from "../storage/TermMaxStorageV2.sol";

/**
 * @title TermMax Vault Factory Interface v2
 * @author Term Structure Labs
 * @notice Interface for creating new TermMax vaults
 */
interface ITermMaxVaultFactoryV2 {
    /**
     * @notice The implementation of TermMax Vault contract
     */
    function TERMMAX_VAULT_IMPLEMENTATION() external view returns (address);

    /**
     * @notice Predict the address of a new TermMax vault
     * @param deployer The address of the vault deployer
     * @param asset The address of the asset
     * @param name The name of the vault
     * @param symbol The symbol of the vault
     * @param salt The salt used to create the vault
     * @return vault The predicted address of the vault
     */
    function predictVaultAddress(
        address deployer,
        address asset,
        string memory name,
        string memory symbol,
        uint256 salt
    ) external view returns (address vault);

    /**
     * @notice Creates a new TermMax vault with the specified parameters
     * @param initialParams Initial parameters for vault configuration
     * @param salt The salt used to create the vault
     * @return address The address of the newly created vault
     */
    function createVault(VaultInitialParamsV2 memory initialParams, uint256 salt) external returns (address);
}
