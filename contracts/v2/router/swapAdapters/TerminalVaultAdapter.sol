// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";
import {ITerminalVault} from "../../extensions/terminal/ITerminalVault.sol";
import {ERC4626VaultAdapterV2} from "./ERC4626VaultAdapterV2.sol";

/**
 * @title The adapter for terminal vault
 * @author Term Structure Labs
 */
contract TerminalVaultAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (
            ERC4626VaultAdapterV2.Action action,
            ITerminalVault vault,
            uint256 inAmount,
            uint256 minReceiveAmount,
            bytes32 referrerId
        ) = abi.decode(swapData, (ERC4626VaultAdapterV2.Action, ITerminalVault, uint256, uint256, bytes32));
        /**
         * Note: Scaling Input/Output amount (round up)
         */
        minReceiveAmount = minReceiveAmount.mulDiv(amount, inAmount, Math.Rounding.Ceil);
        if (action == ERC4626VaultAdapterV2.Action.Redeem) {
            vault.redeemInstant(address(tokenOut), amount, minReceiveAmount);
        } else if (action == ERC4626VaultAdapterV2.Action.Deposit) {
            tokenIn.safeIncreaseAllowance(address(vault), amount);
            vault.depositInstant(address(tokenIn), amount, minReceiveAmount, referrerId);
        } else {
            revert ERC4626VaultAdapterV2.InvalidAction();
        }

        tokenOutAmt = tokenOut.balanceOf(address(this));
        require(tokenOutAmt >= minReceiveAmount, LessThanMinTokenOut(tokenOutAmt, minReceiveAmount));
        if (recipient != address(this)) {
            tokenOut.safeTransfer(recipient, tokenOutAmt);
        }
    }
}
