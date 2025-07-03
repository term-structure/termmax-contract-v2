// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "../v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "../v1/tokens/IGearingToken.sol";
import {OrderConfig, MarketConfig} from "../v1/storage/TermMaxStorage.sol";
import {OrderInitialParams} from "./storage/TermMaxStorageV2.sol";
/**
 * @title TermMax Order interface v2
 * @author Term Structure Labs
 */

interface ITermMaxOrderV2 {
    /// @notice Initialize the token and configuration of the order
    function initialize(OrderInitialParams memory params) external;
}
