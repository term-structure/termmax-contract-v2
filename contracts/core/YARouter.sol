// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IYARouter.sol";
contract YARouter is IYARouter, AccessControlUpgradeable, UUPSUpgradeable{

    function initialize(address admin) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE){}
}