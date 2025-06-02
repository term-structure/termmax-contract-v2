// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../v1/access/AccessManager.sol";
import {IOracleV2} from "../oracle/IOracleV2.sol";

/**
 * @title TermMax Access Manager V2
 * @author Term Structure Labs
 */
contract AccessManagerV2 is AccessManager {
    /// @notice Set the switch of multiple entities
    function batchSetSwitch(IPausable[] calldata entities, bool state) external onlyRole(PAUSER_ROLE) {
        for (uint256 i = 0; i < entities.length; i++) {
            if (state) {
                entities[i].unpause();
            } else {
                entities[i].pause();
            }
        }
    }

    function submitPendingOracle(IOracleV2 aggregator, address asset, IOracleV2.Oracle memory oracle)
        external
        onlyRole(ORACLE_ROLE)
    {
        aggregator.submitPendingOracle(asset, oracle);
    }

    function revokePendingOracle(IOracleV2 aggregator, address asset) external onlyRole(ORACLE_ROLE) {
        aggregator.revokePendingOracle(asset);
    }
}
