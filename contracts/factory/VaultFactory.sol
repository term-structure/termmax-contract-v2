// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultInitialParams} from "contracts/storage/TermMaxStorage.sol";
import {FactoryEvents} from "contracts/events/FactoryEvents.sol";

contract VaultFactory is FactoryEvents {
    function createVault(VaultInitialParams memory initialParams) public returns (TermMaxVault vault) {
        vault = new TermMaxVault(initialParams);
        emit VaultCreated(address(vault), msg.sender, initialParams);
    }
}
