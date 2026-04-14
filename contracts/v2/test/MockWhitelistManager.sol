// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWhitelistManager} from "../access/IWhitelistManager.sol";

contract MockWhitelistManager is IWhitelistManager {
    mapping(address => mapping(ContractModule => bool)) public whitelist;

    function setWhitelist(address _user, ContractModule _module, bool _approved) external {
        whitelist[_user][_module] = _approved;
    }

    function batchSetWhitelist(address[] memory _addresses, ContractModule _module, bool _approved) external {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]][_module] = _approved;
        }

        emit WhitelistUpdated(_addresses, _module, _approved);
    }

    function isWhitelisted(address _user, ContractModule _module) external view returns (bool) {
        return whitelist[_user][_module];
    }
}
