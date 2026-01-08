// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";
import {IOneInchRouter} from "../../extensions/1inch/IOneInchRouter.sol";

/**
 * @title TermMax 1inch Swap Adapter
 * @author Term Structure Labs
 */
contract OneInchSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    error PartialSpend(uint256 spentAmount, uint256 expectedAmount);

    IOneInchRouter public immutable router;

    constructor(address router_) {
        router = IOneInchRouter(router_);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20, uint256 amountIn, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        tokenIn.safeApprove(address(router), amountIn);
        (address executor, IOneInchRouter.SwapDescription memory desc, bytes memory data) =
            abi.decode(swapData, (address, IOneInchRouter.SwapDescription, bytes));
        desc.dstReceiver = payable(recipient);

        if (desc.amount != amountIn) {
            // scale amount
            desc.minReturnAmount = desc.minReturnAmount.mulDiv(amountIn, desc.amount, Math.Rounding.Ceil);
            desc.amount = amountIn;
        }

        (uint256 returnAmount, uint256 spentAmount) = router.swap(executor, desc, data);
        // check partial spend
        require(spentAmount == amountIn, PartialSpend(spentAmount, amountIn));
        tokenOutAmt = returnAmount;
    }
}
