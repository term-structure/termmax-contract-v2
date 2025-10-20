// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OKXScaleHelper} from "contracts/v1/extensions/OKXScaleHelper.sol";
import "./ERC20SwapAdapterV2.sol";
/**
 * @title TermMax OkxSwapAdapter
 * @author Term Structure Labs
 */

contract OkxSwapAdapter is ERC20SwapAdapterV2, OKXScaleHelper {
    using TransferUtilsV2 for IERC20;
    address router = 0x2E1Dee213BA8d7af0934C49a23187BabEACa8764; 

    constructor() {}

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        onlyProxy
        returns (uint256 tokenOutAmt)
    {
        address approvalAddress = _okx_getTokenApprove();
        IERC20(tokenIn).safeIncreaseAllowance(approvalAddress, amount);
        uint256 balanceBefore = tokenOut.balanceOf(address(this));
        (bool success, bytes memory returnData) = router.call(_okxScaling(swapData, amount));
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        tokenOutAmt = tokenOut.balanceOf(address(this)) - balanceBefore;
        tokenOut.safeTransfer(recipient, tokenOutAmt);
    }
}
