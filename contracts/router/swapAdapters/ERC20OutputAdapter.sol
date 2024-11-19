// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapAdapter} from "../ISwapAdapter.sol";

abstract contract ERC20OutputAdapter is ISwapAdapter {
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
