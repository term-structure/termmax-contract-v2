// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";

/**
 * @title TermMax PancakeSmartAdapter
 * @notice This adapter enables swaps via PancakeSwap's Universal Router.
 *         Make sure to use exact input/output amounts without scaling because PancakeSwap's universal router don't support it.
 * @author Term Structure Labs
 */
contract PancakeSmartAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    error InvalidTradeAmount();

    address public immutable router;

    constructor(address _pancakeRouter) {
        router = _pancakeRouter;
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (bytes memory data, bool isExactOut, uint256 tradeAmount, uint256 netAmount, address refundAddress) =
            abi.decode(swapData, (bytes, bool, uint256, uint256, address));
        if (tradeAmount != amount && !isExactOut) {
            revert InvalidTradeAmount();
        }
        ///@dev make sure the recipient in swapdata is this contract
        uint256 tokenInBalBefore = tokenIn.balanceOf(address(this));
        uint256 tokenOutBalBefore = tokenOut.balanceOf(address(this));
        if (isExactOut) {
            if (amount < netAmount) revert InvalidTradeAmount();
            tokenIn.safeApprove(address(router), netAmount);
        } else {
            if (amount != tradeAmount) revert InvalidTradeAmount();
            tokenIn.safeApprove(address(router), amount);
        }
        (bool success, bytes memory returnData) = router.call{value: 0}(data);
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        uint256 realCost = tokenInBalBefore - tokenIn.balanceOf(address(this));
        uint256 realReceived = tokenOut.balanceOf(address(this)) - tokenOutBalBefore;
        if (isExactOut) {
            //refund excess input tokens
            if (amount > realCost && refundAddress != address(0) && refundAddress != address(this)) {
                tokenIn.safeTransfer(refundAddress, amount - realCost);
            }
            if (realCost > netAmount) revert ExceedMaxTokenIn(realCost, tradeAmount);
            tokenOutAmt = realReceived;
        } else {
            if (realReceived < netAmount) revert LessThanMinTokenOut(realReceived, netAmount);
            tokenOutAmt = realReceived;
        }
        tokenOut.safeTransfer(recipient, tokenOutAmt);
    }
}
