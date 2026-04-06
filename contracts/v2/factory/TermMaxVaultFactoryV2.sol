// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ITermMaxVaultV2} from "../vault/ITermMaxVaultV2.sol";
import {FactoryEventsV2} from "../events/FactoryEventsV2.sol";
import {ITermMaxVaultFactoryV2} from "./ITermMaxVaultFactoryV2.sol";
import {VaultInitialParamsV2} from "../storage/TermMaxStorageV2.sol";
import {WithAccessManagerRole} from "../access/WithAccessManagerRole.sol";
import {WithWhitelistCheck, IWhitelistManager} from "../access/WithWhitelistCheck.sol";
import {VersionV2} from "../VersionV2.sol";

/**
 * @title The TermMax vault factory v2
 * @author Term Structure Labs
 */
contract TermMaxVaultFactoryV2 is ITermMaxVaultFactoryV2, VersionV2, WithWhitelistCheck, WithAccessManagerRole {
    /**
     * @notice The implementation of TermMax Vault contract v2
     */
    address public immutable TERMMAX_VAULT_IMPLEMENTATION;

    constructor(address accessManager, address TERMMAX_VAULT_IMPLEMENTATION_, address _whitelistManager)
        WithAccessManagerRole(accessManager)
        WithWhitelistCheck(_whitelistManager, IWhitelistManager.ContractModule.ORDER_CALLBACK)
    {
        TERMMAX_VAULT_IMPLEMENTATION = TERMMAX_VAULT_IMPLEMENTATION_;
    }

    /**
     * @inheritdoc ITermMaxVaultFactoryV2
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

    function _getRegistry() internal view override returns (address) {
        return ACCESS_MANAGER;
    }

    /**
     * @inheritdoc ITermMaxVaultFactoryV2
     */
    function createVault(VaultInitialParamsV2 memory initialParams, uint256 salt)
        public
        hasRole(VAULT_DEPLOYER_ROLE)
        returns (address vault)
    {
        vault = Clones.cloneDeterministic(
            TERMMAX_VAULT_IMPLEMENTATION,
            keccak256(abi.encode(msg.sender, initialParams.asset, initialParams.name, initialParams.symbol, salt))
        );
        ITermMaxVaultV2(vault).initialize(initialParams);
        _registerAddress(vault);
        emit FactoryEventsV2.VaultCreated(vault, msg.sender, initialParams);
    }
}
