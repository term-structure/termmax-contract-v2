// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwapCallback {
    function swapCallback(int256 deltaFt, int256 deltaXt) external;
}
