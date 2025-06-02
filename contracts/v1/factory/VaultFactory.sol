// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ITermMaxVault} from "../vault/ITermMaxVault.sol";
import {VaultInitialParams} from "../storage/TermMaxStorage.sol";
import {FactoryEvents} from "../events/FactoryEvents.sol";
import {FactoryErrors} from "../errors/FactoryErrors.sol";
import {IVaultFactory} from "./IVaultFactory.sol";

/**
 * @title The TermMax vault factory
 * @author Term Structure Labs
 */
contract VaultFactory is FactoryEvents, IVaultFactory, FactoryErrors {
    /**
     * @notice The implementation of TermMax Vault contract
     */
    address public immutable TERMMAX_VAULT_IMPLEMENTATION;

    constructor(address TERMMAX_VAULT_IMPLEMENTATION_) {
        if (TERMMAX_VAULT_IMPLEMENTATION_ == address(0)) {
            revert InvalidImplementation();
        }
        TERMMAX_VAULT_IMPLEMENTATION = TERMMAX_VAULT_IMPLEMENTATION_;
    }

    /**
     * @inheritdoc IVaultFactory
     */
    function predictVaultAddress(
        address deployer,
        address asset,
        string memory name,
        string memory symbol,
        uint256 salt
    ) external view returns (address vault) {
        return Clones.predictDeterministicAddress(
            TERMMAX_VAULT_IMPLEMENTATION, keccak256(abi.encode(deployer, asset, name, symbol, salt))
        );
    }

    /**
     * @inheritdoc IVaultFactory
     */
    function createVault(VaultInitialParams memory initialParams, uint256 salt) public returns (address vault) {
        vault = Clones.cloneDeterministic(
            TERMMAX_VAULT_IMPLEMENTATION,
            keccak256(abi.encode(msg.sender, initialParams.asset, initialParams.name, initialParams.symbol, salt))
        );
        ITermMaxVault(vault).initialize(initialParams);
        emit CreateVault(vault, msg.sender, initialParams);
    }
}
