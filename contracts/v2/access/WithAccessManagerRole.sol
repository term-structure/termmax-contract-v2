// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "./Roles.sol";
/**
 * @notice Reuse OpenZeppelin onlyRole while delegating role checks to AccessManager.
 */

abstract contract WithAccessManagerRole is Roles {
    address public immutable ACCESS_MANAGER;

    constructor(address accessManager) {
        ACCESS_MANAGER = accessManager;
    }

    modifier hasRole(bytes32 role) {
        if (msg.sender != ACCESS_MANAGER) {
            require(
                IAccessControl(ACCESS_MANAGER).hasRole(role, msg.sender),
                IAccessControl.AccessControlUnauthorizedAccount(msg.sender, role)
            );
        }
        _;
    }
}
