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
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amount);
        (bytes memory path, uint256 deadline, uint256 inAmount, uint256 amountOutMinimum) =
            abi.decode(swapData, (bytes, uint256, uint256, uint256));
        /**
         * Note: Scaling Input/Output amount
         */
        amountOutMinimum = amountOutMinimum.mulDiv(amount, inAmount, Math.Rounding.Ceil);

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
