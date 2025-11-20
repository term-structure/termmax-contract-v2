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

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        onlyProxy
        returns (uint256 tokenOutAmt)
    {
        (address router, address okxApproveAddress, bytes memory data) = abi.decode(swapData, (address, address, bytes));

        IERC20(tokenIn).safeApprove(okxApproveAddress, amount);
        // scale the swapData and set the receiver to this contract(OkxDexRouter may not
        // support transferring to arbitrary address)
        data = _okxScaling(data, amount, address(this));
        (bool success, bytes memory returnData) = router.call(data);
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        tokenOutAmt = abi.decode(returnData, (uint256));
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
