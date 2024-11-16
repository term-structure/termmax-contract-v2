// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ISwapAdapter} from "./ISwapAdapter.sol";

contract SwapAdapter is ISwapAdapter {
    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory inputData,
        bytes memory swapData
    ) external override returns (bytes memory tokenOutData) {}
}
