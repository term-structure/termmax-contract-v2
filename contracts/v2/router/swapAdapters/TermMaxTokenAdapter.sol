// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./ERC20SwapAdapterV2.sol";
import {ITermMaxToken} from "../../tokens/ITermMaxToken.sol";

/**
 * @title TermMaxTokenAdapter
 * @notice Swap adapter for TermMax native tokens that support mint/burn operations
 * @dev This adapter enables seamless token conversion between TermMax tokens and their underlying assets
 *      through mint and burn operations rather than traditional swaps. It's designed to work with
 *      tokens that implement the ITermMaxToken interface.
 *
 * @dev Usage patterns:
 *      - Wrapping: Convert underlying asset to TermMax token via mint operation
 *      - Unwrapping: Convert TermMax token back to underlying asset via burn operation
 *
 * @dev The adapter maintains a 1:1 conversion ratio between input and output tokens,
 *      making it suitable for wrapped token scenarios where no price discovery is needed.
 */
contract TermMaxTokenAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    /**
     * @notice Performs token conversion through mint/burn operations
     * @dev Overrides the base swap function to implement TermMax token-specific logic
     *
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param tokenInAmt The amount of input tokens to convert
     * @param swapData Encoded boolean indicating operation type:
     *                 - true: Wrap operation (mint tokenOut using tokenIn)
     *                 - false: Unwrap operation (burn tokenIn to get underlying)
     *
     * @return tokenOutAmt The amount of output tokens received (always equals tokenInAmt for 1:1 conversion)
     *
     * @dev Security considerations:
     *      - Assumes caller has already transferred tokenInAmt to this contract
     *      - For wrap operations: tokenOut must implement ITermMaxToken.mint()
     *      - For unwrap operations: tokenIn must implement ITermMaxToken.burn()
     *      - No slippage protection needed due to 1:1 conversion ratio
     */

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        // Decode the operation type from swap data
        bool isWrap = abi.decode(swapData, (bool));

        if (isWrap) {
            // Wrap operation: Mint new TermMax tokens
            // tokenOut must be a TermMax token that supports minting
            tokenIn.safeIncreaseAllowance(address(tokenOut), tokenInAmt);
            ITermMaxToken(address(tokenOut)).mint(recipient, tokenInAmt);
        } else {
            // Unwrap operation: Burn existing TermMax tokens
            // tokenIn must be a TermMax token that supports burning
            ITermMaxToken(address(tokenIn)).burn(recipient, tokenInAmt);
        }

        // Return the same amount due to 1:1 conversion ratio
        tokenOutAmt = tokenInAmt;
    }
}
