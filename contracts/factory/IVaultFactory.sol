// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultInitialParams} from "contracts/storage/TermMaxStorage.sol";

/**
 * @title TermMax Vault Factory Interface
 * @author Term Structure Labs
 * @notice Interface for creating new TermMax vaults
 */
interface IVaultFactory {
    /**
     * @notice Creates a new TermMax vault with the specified parameters
     * @param initialParams Initial parameters for vault configuration
     * @return address The address of the newly created vault
     */
    function createVault(VaultInitialParams memory initialParams) external returns (address);
}
