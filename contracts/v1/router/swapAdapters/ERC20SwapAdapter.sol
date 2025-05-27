// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferUtils} from "../../lib/TransferUtils.sol";
import {ISwapAdapter} from "../ISwapAdapter.sol";

/**
 * @title TermMax ERC20SwapAdapter
 * @author Term Structure Labs
 */
abstract contract ERC20SwapAdapter is ISwapAdapter {
    using TransferUtils for IERC20;

    /// @notice Error for partial swap
    error ERC20InvalidPartialSwap(uint256 expectedTradeAmt, uint256 actualTradeAmt);

    /// @notice Error for less than min token out
    error LessThanMinTokenOut(uint256 actual, uint256 expected);

    /**
     * @inheritdoc ISwapAdapter
     */
    function swap(address tokenIn, address tokenOut, bytes memory tokenInData, bytes memory swapData)
        external
        override
        returns (bytes memory tokenOutData)
    {
        uint256 tokenInAmt = _decodeAmount(tokenInData);

        uint256 tokenInAmtBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 tokenOutAmt = _swap(IERC20(tokenIn), IERC20(tokenOut), tokenInAmt, swapData);
        uint256 tokenInAmtAfter = IERC20(tokenIn).balanceOf(address(this));

        // Check partial swap
        if (tokenInAmtAfter + tokenInAmt != tokenInAmtBefore) {
            revert ERC20InvalidPartialSwap(tokenInAmt, tokenInAmtBefore - tokenInAmtAfter);
        }
        tokenOutData = _encodeAmount(tokenOutAmt);
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        returns (uint256 tokenOutAmt);

    /**
     * @inheritdoc ISwapAdapter
     */
    function approveOutputToken(address token, address spender, bytes memory tokenData) external override {
        IERC20(token).safeIncreaseAllowance(spender, _decodeAmount(tokenData));
    }

    /**
     * @inheritdoc ISwapAdapter
     */
    function transferOutputToken(address token, address to, bytes memory tokenData) external override {
        IERC20(token).safeTransfer(to, _decodeAmount(tokenData));
    }

    /**
     * @inheritdoc ISwapAdapter
     */
    function transferInputTokenFrom(address token, address from, address to, bytes memory tokenData)
        external
        override
    {
        IERC20(token).safeTransferFrom(from, to, _decodeAmount(tokenData));
    }

    /// @notice Encode uin256 to bytes
    function _encodeAmount(uint256 amount) internal pure returns (bytes memory data) {
        data = abi.encode(amount);
    }

    /// @notice Decode uin256 from bytes
    function _decodeAmount(bytes memory data) internal pure returns (uint256 amount) {
        amount = abi.decode(data, (uint256));
    }
}
