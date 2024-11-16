// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ISwapAdapter {
    // leverage, underlying in, collateral out, return collateralAmt
    // flashRepay, collateral in, cash out
    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory inputData,
        bytes memory swapData
    ) external returns (bytes memory tokenOutData);
}
