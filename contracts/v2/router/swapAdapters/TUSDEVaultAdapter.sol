// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20SwapAdapterV2.sol";
import {ITUSDEVault} from "../../extensions/tUSDE/ITUSDEVault.sol";
import {ERC4626VaultAdapterV2} from "./ERC4626VaultAdapterV2.sol";

/**
 * @title The adapter for tUSDE vault
 * @author Term Structure Labs
 */
contract TUSDEVaultAdapter is ERC20SwapAdapterV2 {
    using TransferUtilsV2 for IERC20;
    using Math for uint256;

    /// @notice The tUSDE redeem vault, supports redeem tUSDE to sUSDE
    ITUSDEVault public immutable redeemVault;
    /// @notice The tUSDE deposit vault, supports deposit USDE to tUSDE
    ITUSDEVault public immutable depositVault;

    constructor(address _redeemVault, address _depositVault) {
        redeemVault = ITUSDEVault(_redeemVault);
        depositVault = ITUSDEVault(_depositVault);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (ERC4626VaultAdapterV2.Action action, uint256 inAmount, uint256 minReceiveAmount, bytes32 referrerId) =
            abi.decode(swapData, (ERC4626VaultAdapterV2.Action, uint256, uint256, bytes32));
        /**
         * Note: Scaling Input/Output amount (round up)
         */
        minReceiveAmount = minReceiveAmount.mulDiv(amount, inAmount, Math.Rounding.Ceil);
        if (action == ERC4626VaultAdapterV2.Action.Redeem) {
            redeemVault.redeemInstant(address(tokenOut), amount, minReceiveAmount);
        } else if (action == ERC4626VaultAdapterV2.Action.Deposit) {
            tokenIn.safeIncreaseAllowance(address(depositVault), amount);
            depositVault.depositInstant(address(tokenIn), amount, minReceiveAmount, referrerId);
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
