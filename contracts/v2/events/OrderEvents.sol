// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20, ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts, FeeConfig} from "../storage/TermMaxStorage.sol";
interface OrderEvents {
    /// @notice Emitted when order initialized
    /// @param market The market
    event OrderInitialized(ITermMaxMarket indexed market, address maker, CurveCuts curveCuts);

    event UpdateFeeConfig(FeeConfig feeConfig);

    /// @notice Emitted when update order
    event UpdateOrder(CurveCuts curveCuts, uint256 ftReserve, uint256 xtReserve, uint256 gtId);

    /// @notice Emitted when swap exact token to token
    /// @param caller Who call the function
    /// @param recipient Who receive output tokens
    /// @param tokenIn The token want to swap
    /// @param tokenOut The token want to receive
    /// @param tokenAmtIn The amount of tokenIn want to swap
    /// @param netTokenOut The amount of tokenOut want to receive
    event SwapExactTokenToToken(
        address indexed caller,
        address indexed recipient,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint128 tokenAmtIn,
        uint128 netTokenOut,
        uint128 feeAmt
    );
}
