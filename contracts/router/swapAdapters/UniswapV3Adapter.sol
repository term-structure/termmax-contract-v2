// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./ERC20SwapAdapter.sol";

/**
 * @title TermMax UniswapV3Adapter
 * @author Term Structure Labs
 */
contract UniswapV3Adapter is ERC20SwapAdapter {
    ISwapRouter public immutable router;

    constructor(address router_) {
        router = ISwapRouter(router_);
    }

    function _swap(IERC20 tokenIn, IERC20, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        IERC20(tokenIn).approve(address(router), amount);
        (bytes memory path, uint256 deadline, uint256 inAmount, uint256 amountOutMinimum) =
            abi.decode(swapData, (bytes, uint256, uint256, uint256));
        /**
         * Note: Scaling Input/Output amount
         */
        amountOutMinimum = (amountOutMinimum * amount) / inAmount;

        tokenOutAmt = router.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amount,
                amountOutMinimum: amountOutMinimum
            })
        );
    }
}
