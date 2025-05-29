// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMintableERC20 as IMintableERC20V1} from "../v1/tokens/IMintableERC20.sol";
import {IMintableERC20V2} from "../v2/tokens/IMintableERC20V2.sol";

/**
 * @title Mintable ERC20 interface
 * @author Term Structure Labs
 */
interface IMintableERC20 is IMintableERC20V1, IMintableERC20V2 {}
