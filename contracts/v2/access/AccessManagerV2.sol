// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../v1/access/AccessManager.sol";
import {IOracleV2} from "../oracle/IOracleV2.sol";
import {ITermMaxVaultV2, OrderV2ConfigurationParams, CurveCuts} from "../vault/ITermMaxVaultV2.sol";

/**
 * @title TermMax Access Manager V2
 * @author Term Structure Labs
 * @notice Extended access manager for TermMax V2 protocol with additional oracle and batch operations
 * @dev Inherits from AccessManager V1 and adds V2-specific functionality for managing oracles and batch operations
 */
contract AccessManagerV2 is AccessManager {
    error CannotRenounceRole();
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

    /// @notice Forbid renouncing roles
    function renounceRole(bytes32 role, address callerConfirmation) public override {
        revert CannotRenounceRole();
    }
}
