// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITermMaxOrder as ITermMaxOrderV1} from "../v1/ITermMaxOrder.sol";
import {ITermMaxOrderV2} from "../v2/ITermMaxOrderV2.sol";

/**
 * @title TermMax Order interface
 * @author Term Structure Labs
 */
interface ITermMaxOrder is ITermMaxOrderV1, ITermMaxOrderV2 {}
