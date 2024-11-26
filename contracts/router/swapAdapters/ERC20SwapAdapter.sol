// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapAdapter} from "../ISwapAdapter.sol";

abstract contract ERC20SwapAdapter is ISwapAdapter {
    error ERC20InvalidPartialSwap(
        uint256 expectedTradeAmt,
        uint256 actualTradeAmt
    );

    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory tokenInData,
        bytes memory swapData
    ) external override returns (bytes memory tokenOutData) {
        uint256 tokenInAmt = _decodeAmount(tokenInData);

        uint256 tokenInAmtBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 tokenOutAmt = _swap(
            IERC20(tokenIn),
            IERC20(tokenOut),
            tokenInAmt,
            swapData
        );
        uint256 tokenInAmtAfter = IERC20(tokenIn).balanceOf(address(this));

        // Check partial swap
        if (tokenInAmtAfter + tokenInAmt != tokenInAmtBefore) {
            revert ERC20InvalidPartialSwap(
                tokenInAmt,
                tokenInAmtBefore - tokenInAmtAfter
            );
        }
        tokenOutData = _encodeAmount(tokenOutAmt);
    }

    function _swap(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 tokenInAmt,
        bytes memory swapData
    ) internal virtual returns (uint256 tokenOutAmt);

    function approveOutputToken(
        address token,
        address spender,
        bytes memory tokenData
    ) external override {
        IERC20(token).approve(spender, _decodeAmount(tokenData));
    }

    function transferOutputToken(
        address token,
        address to,
        bytes memory tokenData
    ) external override {
        IERC20(token).transfer(to, _decodeAmount(tokenData));
    }

    function transferInputTokenFrom(
        address token,
        address from,
        address to,
        bytes memory tokenData
    ) external override {
        IERC20(token).transferFrom(from, to, _decodeAmount(tokenData));
    }

    function _encodeAmount(
        uint256 amount
    ) internal pure returns (bytes memory data) {
        data = abi.encode(amount);
    }

    function _decodeAmount(
        bytes memory data
    ) internal pure returns (uint256 amount) {
        amount = abi.decode(data, (uint256));
    }
}
