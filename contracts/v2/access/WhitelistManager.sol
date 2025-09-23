// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IWhitelistManager} from "./IWhitelistManager.sol";
import {VersionV2} from "../VersionV2.sol";

/**
 * @title WhitelistManager
 * @author Term Structure Labs
 * @notice Manages whitelists for different contract modules such as adapters, order callbacks, and markets
 * @dev This contract uses UUPS upgradeability and Ownable2Step for ownership management
 */
contract WhitelistManager is IWhitelistManager, UUPSUpgradeable, Ownable2StepUpgradeable, VersionV2 {
    mapping(ContractModule => mapping(address => bool)) private whitelists;

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init_unchained();
        __Ownable_init_unchained(admin);
    }

    function _setWhitelist(address[] memory contractAddresses, ContractModule module, bool approved) internal {
        mapping(address => bool) storage moduleWhitelists = whitelists[module];
        for (uint256 i = 0; i < contractAddresses.length; ++i) {
            moduleWhitelists[contractAddresses[i]] = approved;
        }
        emit WhitelistUpdated(contractAddresses, module, approved);
    }

    function batchSetWhitelist(address[] memory contractAddresses, ContractModule module, bool approved)
        external
        onlyOwner
    {
        _setWhitelist(contractAddresses, module, approved);
    }

    function isWhitelisted(address contractAddress, ContractModule module) external view returns (bool) {
        return whitelists[module][contractAddress];
    }
}
