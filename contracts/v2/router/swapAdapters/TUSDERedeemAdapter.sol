// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";
import {ITUSDEVault} from "../../extensions/tUSDE/ITUSDEVault.sol";

/**
 * @title The redeem adapter for tUSDE vault
 * @author Term Structure Labs
 */
contract TUSDERedeemAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    function _swap(address recipient, IERC20, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (ITUSDEVault tUSDEVault, uint256 inAmount, uint256 minReceiveAmount) =
            abi.decode(swapData, (ITUSDEVault, uint256, uint256));
        /**
         * Note: Scaling Input/Output amount (round up)
         */
        minReceiveAmount = minReceiveAmount.mulDiv(amount, inAmount, Math.Rounding.Ceil);
        tUSDEVault.redeemInstant(address(tokenOut), amount, minReceiveAmount);
        tokenOutAmt = tokenOut.balanceOf(address(this));
        require(tokenOutAmt >= minReceiveAmount, LessThanMinTokenOut(tokenOutAmt, minReceiveAmount));
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
