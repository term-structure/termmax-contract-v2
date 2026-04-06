// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "./Roles.sol";
/**
 * @notice Reuse OpenZeppelin onlyRole while delegating role checks to AccessManager.
 */

abstract contract WithAccessManagerRole is AccessControl, Roles {
    address public immutable ACCESS_MANAGER;

    constructor(address accessManager) {
        ACCESS_MANAGER = accessManager;
    }

    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return IAccessControl(ACCESS_MANAGER).hasRole(role, account);
    }
}
