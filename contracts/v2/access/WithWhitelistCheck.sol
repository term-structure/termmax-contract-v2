// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWhitelistManager} from "./IWhitelistManager.sol";

abstract contract WithWhitelistCheck {
    error WhitelistManagerNotSet();
    error NoWhitelistModuleConfigured();
    error TargetNotWhitelisted();

    IWhitelistManager public immutable whitelistManager;
    IWhitelistManager.ContractModule public immutable defaultWhitelistModule;

    constructor(address _whitelistManager, IWhitelistManager.ContractModule _defaultWhitelistModule) {
        if (_whitelistManager == address(0)) revert WhitelistManagerNotSet();
        whitelistManager = IWhitelistManager(_whitelistManager);
        defaultWhitelistModule = _defaultWhitelistModule;
    }

    function _registerAddress(address target) internal {
        _registerAddressWithModule(target, defaultWhitelistModule);
    }

    function _registerAddressWithModule(address target, IWhitelistManager.ContractModule module) internal {
        address[] memory targets = new address[](1);
        targets[0] = target;
        whitelistManager.batchSetWhitelist(targets, module, true);
    }

    function _checkWhitelisted(address target, IWhitelistManager.ContractModule module) internal view {
        if (!whitelistManager.isWhitelisted(target, module)) revert TargetNotWhitelisted();
    }

    function _checkWhitelisted(address target) internal view {
        _checkWhitelisted(target, defaultWhitelistModule);
    }

    modifier onlyWhitelisted(address target) {
        _checkWhitelisted(target);
        _;
    }

    modifier onlyWhitelistedWithModule(address target, IWhitelistManager.ContractModule module) {
        _checkWhitelisted(target, module);
        _;
    }
}
