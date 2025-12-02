// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./ERC20SwapAdapterV2.sol";

/**
 * @title TermMax UniswapV3AdapterV2
 * @author Term Structure Labs
 */
contract UniswapV3AdapterV2 is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    function _swap(address recipient, IERC20 tokenIn, IERC20, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (
            ISwapRouter router,
            bytes memory path,
            bool isExactOut,
            uint256 deadline,
            uint256 tradeAmount,
            uint256 netAmount,
            address refundAddress
        ) = abi.decode(swapData, (ISwapRouter, bytes, bool, uint256, uint256, uint256, address));
        if (isExactOut) {
            IERC20(tokenIn).safeApprove(address(router), netAmount);
            uint256 amountIn = router.exactOutput(
                ISwapRouter.ExactOutputParams({
                    path: path,
                    recipient: recipient,
                    deadline: deadline,
                    amountOut: tradeAmount,
                    amountInMaximum: netAmount
                })
            );
            // refund remaining tokenIn to refundAddress
            if (refundAddress != address(0) && refundAddress != address(this) && amount > amountIn) {
                tokenIn.safeTransfer(refundAddress, amount - amountIn);
            }
            tokenOutAmt = tradeAmount;
        } else {
            IERC20(tokenIn).safeApprove(address(router), amount);
            /**
             * Note: Scaling Input/Output amount
             */
            tradeAmount = tradeAmount.mulDiv(amount, netAmount, Math.Rounding.Ceil);
            tokenOutAmt = router.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path,
                    recipient: recipient,
                    deadline: deadline,
                    amountIn: amount,
                    amountOutMinimum: tradeAmount
                })
            );
        }
    }
}
