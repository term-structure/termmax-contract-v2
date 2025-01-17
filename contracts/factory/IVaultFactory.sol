// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VaultInitialParams} from "contracts/storage/TermMaxStorage.sol";

interface IVaultFactory {
    function createVault(VaultInitialParams memory initialParams) external returns (address);
}
