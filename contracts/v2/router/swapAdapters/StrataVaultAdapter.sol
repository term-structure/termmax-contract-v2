// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";
import {ERC4626VaultAdapterV2} from "./ERC4626VaultAdapterV2.sol";
import {IStrataVault} from "../../extensions/strata/IStrataVault.sol";

/**
 * @title The adapter for strata vault
 * @author Term Structure Labs
 */
contract StrataVaultAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (Action action, uint256 inAmount, uint256 minTokenOut) = abi.decode(swapData, (Action, uint256, uint256));
        /**
         * Note: Scaling Input/Output amount (round up)
         */
        minTokenOut = minTokenOut.mulDiv(amount, inAmount, Math.Rounding.Ceil);

        if (action == ERC4626VaultAdapterV2.Action.Redeem) {
            tokenOutAmt = vault.redeem(address(tokenOut), amount, recipient, address(this));
        } else if (action == ERC4626VaultAdapterV2.Action.Deposit) {
            tokenIn.safeApprove(address(vault), amount);
            tokenOutAmt = vault.deposit(amount, recipient);
        } else {
            revert ERC4626VaultAdapterV2.InvalidAction();
        }

        require(tokenOutAmt >= minTokenOut, LessThanMinTokenOut(tokenOutAmt, minTokenOut));
    }
}
