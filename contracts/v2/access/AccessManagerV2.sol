// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../v1/access/AccessManager.sol";
import {IOracleV2} from "../oracle/IOracleV2.sol";
import {ITermMaxVaultV2, OrderV2ConfigurationParams, CurveCuts} from "../vault/ITermMaxVaultV2.sol";
import {IWhitelistManager} from "./IWhitelistManager.sol";
import {IStableERC4626For4626, StakingBuffer} from "../tokens/IStableERC4626For4626.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {VersionV2_0_1} from "../VersionV2_0_1.sol";

/**
 * @title TermMax Access Manager V2
 * @author Term Structure Labs
 * @notice Extended access manager for TermMax V2 protocol with additional oracle and batch operations
 * @dev Inherits from AccessManager V1 and adds V2-specific functionality for managing oracles and batch operations
 */
contract AccessManagerV2 is AccessManager, VersionV2_0_1 {
    using TransferUtilsV2 for *;

    error CannotRenounceRole();

    function upgradeSubContract(UUPSUpgradeable proxy, address newImplementation, bytes memory data)
        external
        override
        onlyRole(UPGRADER_ROLE)
    {
        proxy.upgradeToAndCall(newImplementation, data);
    }

    function batchSetWhitelist(
        IWhitelistManager whitelistManager,
        address[] calldata contractAddresses,
        IWhitelistManager.ContractModule module,
        bool approved
    ) external onlyRole(WHITELIST_ROLE) {
        whitelistManager.batchSetWhitelist(contractAddresses, module, approved);
    }

    /**
     * @notice Batch pause/unpause multiple entities in a single transaction
     * @dev Allows efficient management of multiple pausable contracts simultaneously
     * @param entities Array of IPausable contracts to pause/unpause
     * @param state True to unpause entities, false to pause them
     * @custom:access Requires PAUSER_ROLE
     * @custom:gas-optimization Uses a simple loop for batch operations
     */
    function batchSetSwitch(IPausable[] calldata entities, bool state) external onlyRole(PAUSER_ROLE) {
        if (state) {
            for (uint256 i = 0; i < entities.length; ++i) {
                entities[i].unpause();
            }
        } else {
            for (uint256 i = 0; i < entities.length; ++i) {
                entities[i].pause();
            }
        }
    }

    /**
     * @notice Submit a pending oracle configuration for a specific asset
     * @dev Allows oracle managers to propose new oracle configurations that can be activated later
     * @param aggregator The oracle aggregator contract to submit the pending oracle to
     * @param asset The asset address for which the oracle is being configured
     * @param oracle The oracle configuration structure containing price feed details
     * @custom:access Requires ORACLE_ROLE
     * @custom:security Oracle updates go through a pending mechanism for security
     */
    function submitPendingOracle(IOracleV2 aggregator, address asset, IOracleV2.Oracle memory oracle)
        external
        onlyRole(ORACLE_ROLE)
    {
        aggregator.submitPendingOracle(asset, oracle);
    }

    /**
     * @notice Revoke a pending oracle configuration for a specific asset
     * @dev Allows oracle managers to cancel pending oracle updates before they are activated
     * @param aggregator The oracle aggregator contract to revoke the pending oracle from
     * @param asset The asset address for which the pending oracle should be revoked
     * @custom:access Requires ORACLE_ROLE
     * @custom:security Provides a way to cancel erroneous oracle submissions
     */
    function revokePendingOracle(IOracleV2 aggregator, address asset) external onlyRole(ORACLE_ROLE) {
        aggregator.revokePendingOracle(asset);
    }

    /**
     * @notice Revoke a pending minimum APY change for the vault
     * @param vault The TermMax vault contract to update
     * @custom:access Requires VAULT_ROLE
     * @custom:security Allows governance to cancel proposed changes before they take effect
     */
    function revokePendingMinApy(ITermMaxVaultV2 vault) external onlyRole(VAULT_ROLE) {
        vault.revokePendingMinApy();
    }

    /**
     * @notice Revoke a pending pool change for the vault
     * @param vault The TermMax vault contract to update
     * @custom:access Requires VAULT_ROLE
     * @custom:security Allows governance to abort pool changes before they take effect
     */
    function revokePendingPool(ITermMaxVaultV2 vault) external onlyRole(VAULT_ROLE) {
        vault.revokePendingPool();
    }

    /**
     * @notice Update stable ERC4626 buffer config and add reserves
     * @param stableERC4626 The stable ERC4626 contract to update
     * @param additionalReserves Additional reserves transferred into the stable ERC4626 contract
     * @param bufferConfig_ New buffer configuration
     * @custom:access Requires STABLE_ERC4626_BUFFER_ROLE
     */
    function updateBufferConfigAndAddReserves(
        IStableERC4626For4626 stableERC4626,
        uint256 additionalReserves,
        StakingBuffer.BufferConfig memory bufferConfig_
    ) external onlyRole(STABLE_ERC4626_BUFFER_ROLE) {
        if (additionalReserves != 0) {
            stableERC4626.safeTransferFrom(msg.sender, address(this), additionalReserves);
            stableERC4626.safeApprove(address(stableERC4626), additionalReserves);
        }
        stableERC4626.updateBufferConfigAndAddReserves(additionalReserves, bufferConfig_);
    }

    /**
     * @notice Withdraw stable ERC4626 income assets
     * @param stableERC4626 The stable ERC4626 contract to withdraw from
     * @param asset Asset address to withdraw (underlying or thirdPool token)
     * @param to Recipient address
     * @param amount Amount of income assets to withdraw
     * @custom:access Requires STABLE_ERC4626_INCOME_WITHDRAW_ROLE
     */
    function withdrawIncomeAssets(IStableERC4626For4626 stableERC4626, address asset, address to, uint256 amount)
        external
        onlyRole(STABLE_ERC4626_INCOME_WITHDRAW_ROLE)
    {
        stableERC4626.withdrawIncomeAssets(asset, to, amount);
    }

    /// @notice Forbid renouncing roles
    function renounceRole(bytes32 role, address callerConfirmation) public override {
        revert CannotRenounceRole();
    }
}
