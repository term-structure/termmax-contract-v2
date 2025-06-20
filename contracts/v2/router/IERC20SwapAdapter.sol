// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TermMax ERC20SwapAdapter interface
 * @author Term Structure Labs
 */
interface IERC20SwapAdapter {
    /// @notice Swap tokenIn to tokenOut
    /// @param recipient Address to receive the output tokens
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param tokenInAmt token input amount
    /// @param swapData Encoded swap data
    /// @return tokenOutAmt token output amount
    function swap(address recipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        returns (uint256 tokenOutAmt);
}
