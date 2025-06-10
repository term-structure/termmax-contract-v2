// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "../../v1/tokens/IMintableERC20.sol";
import "../router/swapAdapters/ERC20SwapAdapterV2.sol";

contract MockSwapAdapterV2 is ERC20SwapAdapterV2 {
    address public immutable pool;

    constructor(address pool_) {
        pool = pool_;
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        uint256 minTokenOut = abi.decode(swapData, (uint256));

        IERC20(tokenIn).transfer(pool, amount);

        tokenOutAmt = minTokenOut;
        IMintableERC20(address(tokenOut)).mint(recipient, tokenOutAmt);
    }
}
