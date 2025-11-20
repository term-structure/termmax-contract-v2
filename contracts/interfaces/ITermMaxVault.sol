// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITermMaxVault as ITermMaxVaultV1} from "../v1/vault/ITermMaxVault.sol";
import {ITermMaxVaultV2} from "../v2/vault/ITermMaxVaultV2.sol";

/**
 * @title TermMax Vault interface
 * @author Term Structure Labs
 */
interface ITermMaxVault is ITermMaxVaultV1, ITermMaxVaultV2 {}
