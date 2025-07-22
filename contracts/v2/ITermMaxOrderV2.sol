// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "../v1/tokens/IGearingToken.sol";
import {OrderConfig, MarketConfig} from "../v1/storage/TermMaxStorage.sol";
/**
 * @title TermMax Order interface v2
 * @author Term Structure Labs
 */

interface ITermMaxOrderV2 {
    /// @notice Initialize the token and configuration of the order
    /// @param maker The maker
    /// @param tokens The tokens, [0] = FT, [1] = XT, [2] = debtToken
    /// @param gt The Gearing Token
    /// @param orderConfig The order configuration
    function initialize(
        address maker,
        IERC20[3] memory tokens,
        IGearingToken gt,
        OrderConfig memory orderConfig,
        MarketConfig memory marketConfig
    ) external;
}
