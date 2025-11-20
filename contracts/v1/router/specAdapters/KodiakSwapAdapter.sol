// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IKodiakRouter} from "contracts/v2/extensions/kodiak/IKodiakRouter.sol";
import "./ERC20SwapAdapterV2.sol";

/**
 * @title TermMax KodiakSwapAdapter
 * @author Term Structure Labs
 */
contract KodiakSwapAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (
            IKodiakRouter router,
            IKodiakRouter.InputAmount memory input,
            IKodiakRouter.OutputAmount memory output,
            IKodiakRouter.SwapData memory swapDataStruct,
            IKodiakRouter.FeeData memory feeData
        ) = abi.decode(
            swapData,
            (
                IKodiakRouter,
                IKodiakRouter.InputAmount,
                IKodiakRouter.OutputAmount,
                IKodiakRouter.SwapData,
                IKodiakRouter.FeeData
            )
        );
        /**
         * Note: Scaling Input/Output amount (round up)
         */
        output.minAmountOut = output.minAmountOut.mulDiv(amount, input.amount, Math.Rounding.Ceil);
        input.amount = amount;
        output.receiver = address(this);
        uint256 outputAmountBefore = tokenOut.balanceOf(address(this));
        tokenIn.safeApprove(address(router), amount);
        router.swap(input, output, swapDataStruct, feeData);
        tokenOutAmt = tokenOut.balanceOf(address(this)) - outputAmountBefore;
    }
}
