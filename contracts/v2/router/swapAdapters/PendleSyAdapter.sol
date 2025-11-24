// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStandardizedYield} from "@pendle/core-v2/contracts/interfaces/IStandardizedYield.sol";
import "./ERC20SwapAdapterV2.sol";
import {ERC4626VaultAdapterV2} from "./ERC4626VaultAdapterV2.sol";
/**
 * @title TermMax PendleSyAdapter
 * @author Term Structure Labs
 */

contract PendleSyAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        onlyProxy
        returns (uint256 tokenOutAmt)
    {
        (ERC4626VaultAdapterV2.Action action, uint256 inAmount, uint256 minTokenOut) =
            abi.decode(swapData, (ERC4626VaultAdapterV2.Action, uint256, uint256));

        /**
         * Note: Scaling Input/Output amount
         */
        minTokenOut = minTokenOut.mulDiv(amount, inAmount, Math.Rounding.Ceil);

        bool burnFromInternalBalance = false;
        if (action == ERC4626VaultAdapterV2.Action.Redeem) {
            IStandardizedYield sy = IStandardizedYield(address(tokenIn));
            tokenOutAmt = sy.redeem(recipient, amount, address(tokenOut), minTokenOut, burnFromInternalBalance);
        } else if (action == ERC4626VaultAdapterV2.Action.Deposit) {
            IStandardizedYield sy = IStandardizedYield(address(tokenOut));
            tokenIn.safeApprove(address(sy), amount);
            tokenOutAmt = sy.deposit(recipient, address(tokenIn), amount, minTokenOut);
        } else {
            revert ERC4626VaultAdapterV2.InvalidAction();
        }
    }
}
