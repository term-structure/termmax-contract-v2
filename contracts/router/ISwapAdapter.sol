// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface ISwapAdapter {
    // leverage, underlying in, collateral out, return collateralAmt
    // flashRepay, collateral in, cash out
    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory tokenInData,
        bytes memory swapData
    ) external returns (bytes memory tokenOutData);

    function approveOutputToken(
        address token,
        address spender,
        bytes memory tokenData
    ) external;

    function transferOutputToken(
        address token,
        address to,
        bytes memory tokenData
    ) external;

    function transferInputTokenFrom(
        address token,
        address from,
        address to,
        bytes memory tokenData
    ) external;
}
