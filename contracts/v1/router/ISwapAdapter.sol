// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
/// @notice Swap unit

struct SwapUnit {
    /// @notice Adapter's address
    address adapter;
    /// @notice Input token address
    address tokenIn;
    /// @notice Output token address
    address tokenOut;
    /// @notice Encoded swap data
    bytes swapData;
}

/**
 * @title TermMax SwapAdapter interface
 * @author Term Structure Labs
 */
interface ISwapAdapter {
    /// @notice Swap tokenIn to tokenOut
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param tokenInData Encoded token input data
    /// @param swapData Encoded swap data
    /// @param tokenOutData Encoded token output data
    function swap(address tokenIn, address tokenOut, bytes memory tokenInData, bytes memory swapData)
        external
        returns (bytes memory tokenOutData);

    /// @notice Approve output token
    /// @param token Token address
    /// @param spender Who spend tokens
    /// @param tokenData Encoded token approving data
    function approveOutputToken(address token, address spender, bytes memory tokenData) external;

    /// @notice Transfer output token
    /// @param token Token address
    /// @param to Who receive tokens
    /// @param tokenData Encoded token tranfering data
    function transferOutputToken(address token, address to, bytes memory tokenData) external;

    /// @notice Transfer input token from an address
    /// @param token Token address
    /// @param from Who provide tokens
    /// @param to Who receive tokens
    /// @param tokenData Encoded token tranfering data
    function transferInputTokenFrom(address token, address from, address to, bytes memory tokenData) external;
}
