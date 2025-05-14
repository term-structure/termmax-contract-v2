// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OKXScaleHelper} from "contracts/extensions/OkxHelper.sol";
import "./ERC20SwapAdapter.sol";
/**
 * @title TermMax OkxSwapAdapter
 * @author Term Structure Labs
 */

contract OkxSwapAdapter is ERC20SwapAdapter, OKXScaleHelper {
    using TransferUtils for IERC20;

    constructor() {}

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        address okxRouter = _okx_getTokenApprove();
        IERC20(tokenIn).safeIncreaseAllowance(okxRouter, amount);
        tokenOutAmt = tokenOut.balanceOf(address(this));
        (bool success, bytes memory returnData) = okxRouter.call(_okxScaling(swapData, amount));
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        tokenOutAmt = tokenOut.balanceOf(address(this)) - tokenOutAmt;
    }
}
