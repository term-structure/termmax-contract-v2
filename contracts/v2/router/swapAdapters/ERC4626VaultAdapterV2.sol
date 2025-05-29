// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../v1/router/swapAdapters/ERC4626VaultAdapter.sol";
import {TransferUtils} from "../../../v1/lib/TransferUtils.sol";

/**
 * @title TermMax ERC4626VaultAdapterV2
 * @author Term Structure Labs
 */
contract ERC4626VaultAdapterV2 is ERC4626VaultAdapter {
    using TransferUtils for IERC20;

    constructor() {}

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amount, bytes memory swapData)
        internal
        virtual
        override
        returns (uint256 tokenOutAmt)
    {
        (Action action, uint256 inAmount, uint256 minTokenOut) = abi.decode(swapData, (Action, uint256, uint256));
        /**
         * Note: Scaling Input/Output amount
         */
        minTokenOut = (minTokenOut * amount) / inAmount;

        if (action == Action.Deposit) {
            tokenIn.safeIncreaseAllowance(address(tokenOut), amount);
            tokenOutAmt = IERC4626(address(tokenOut)).deposit(amount, address(this));
            if (tokenOutAmt < minTokenOut) {
                revert LessThanMinTokenOut(tokenOutAmt, minTokenOut);
            }
        } else if (action == Action.Redeem) {
            tokenIn.safeIncreaseAllowance(address(tokenIn), amount);
            tokenOutAmt = IERC4626(address(tokenIn)).redeem(amount, address(this), address(this));
            if (tokenOutAmt < minTokenOut) {
                revert LessThanMinTokenOut(tokenOutAmt, minTokenOut);
            }
        } else {
            revert InvalidAction();
        }
    }
}
