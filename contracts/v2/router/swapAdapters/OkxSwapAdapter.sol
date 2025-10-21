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

    address public immutable router;
    address public immutable okxApproveAddress;

    constructor(address _router, address _okxApproveAddress) {
        router = _router;
        if (_okxApproveAddress == address(0)) {
            _okxApproveAddress = _okx_getTokenApprove();
        }
        okxApproveAddress = _okxApproveAddress;
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        onlyProxy
        returns (uint256 tokenOutAmt)
    {
        address approvalAddress = _okx_getTokenApprove();
        IERC20(tokenIn).safeIncreaseAllowance(approvalAddress, amount);
        // scale the swapData and set the receiver to this contract(OkxDexRouter may not
        // support transferring to arbitrary address)
        bool needtoCheckBalance;
        (needtoCheckBalance, swapData) = _okxScaling(swapData, amount, address(this));
        // some OKX swap functions return the output amount, some don't
        uint256 balanceBefore = needtoCheckBalance ? tokenOut.balanceOf(address(this)) : 0;

        (bool success, bytes memory returnData) = router.call(swapData);
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        tokenOutAmt =
            needtoCheckBalance ? tokenOut.balanceOf(address(this)) - balanceBefore : abi.decode(returnData, (uint256));
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
