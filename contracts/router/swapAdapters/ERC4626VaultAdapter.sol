// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20SwapAdapter} from "../../router/swapAdapters/ERC20SwapAdapter.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TermMax ERC4626VaultAdapter
 * @author Term Structure Labs
 */
contract ERC4626VaultAdapter is ERC20SwapAdapter {
    enum Action {
        Deposit,
        Redeem
    }

    error InvalidAction();

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
            tokenIn.approve(address(tokenOut), amount);
            tokenOutAmt = IERC4626(address(tokenOut)).deposit(amount, address(this));
            if (tokenOutAmt < minTokenOut) {
                revert LessThanMinTokenOut(tokenOutAmt, minTokenOut);
            }
        } else if (action == Action.Redeem) {
            tokenIn.approve(address(tokenIn), amount);
            tokenOutAmt = IERC4626(address(tokenIn)).redeem(amount, address(this), address(this));
            if (tokenOutAmt < minTokenOut) {
                revert LessThanMinTokenOut(tokenOutAmt, minTokenOut);
            }
        } else {
            revert InvalidAction();
        }
    }
}
