// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferUtilsV2} from "../../lib/TransferUtilsV2.sol";
import {IERC20SwapAdapter} from "../IERC20SwapAdapter.sol";
import {OnlyProxyCall} from "../../lib/OnlyProxyCall.sol";

/**
 * @title TermMax ERC20SwapAdapter V2
 * @author Term Structure Labs
 * @notice This contract facilitates ERC20 token swaps with additional features.
 */
abstract contract ERC20SwapAdapterV2 is IERC20SwapAdapter, OnlyProxyCall {
    using TransferUtilsV2 for IERC20;

    /// @notice Error for partial swap
    error ERC20InvalidPartialSwap(uint256 expectedTradeAmt, uint256 actualTradeAmt);

    /// @notice Error for less than min token out
    error LessThanMinTokenOut(uint256 actual, uint256 expected);

    error ExceedMaxTokenIn(uint256 actual, uint256 expected);

    /**
     * @inheritdoc IERC20SwapAdapter
     */
    function swap(address recipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        override
        onlyProxy
        returns (uint256)
    {
        return _swap(recipient, IERC20(tokenIn), IERC20(tokenOut), tokenInAmt, swapData);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        returns (uint256 tokenOutAmt)
    {}
}
