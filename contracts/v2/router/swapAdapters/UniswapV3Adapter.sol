// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../v1/router/swapAdapters/UniswapV3Adapter.sol";

/**
 * @title TermMax UniswapV3AdapterV2
 * @author Term Structure Labs
 */
contract UniswapV3AdapterV2 is UniswapV3Adapter {
    using TransferUtils for IERC20;

    constructor(address router_) UniswapV3Adapter(router_) {}

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
