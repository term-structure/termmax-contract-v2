// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library TransferUtils {
    using SafeERC20 for IERC20;

    error CanNotTransferUintMax();

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        if (value == type(uint256).max) {
            revert CanNotTransferUintMax();
        }
        if (from == to || value == 0) {
            return;
        }
        token.safeTransferFrom(from, to, value);
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if (value == type(uint256).max) {
            revert CanNotTransferUintMax();
        }
        if (to == address(this) || value == 0) {
            return;
        }
        token.safeTransfer(to, value);
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        if (value == 0 || spender == address(this)) {
            return;
        }
        token.safeIncreaseAllowance(spender, value);
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        if (value == 0 || spender == address(this)) {
            return;
        }
        token.safeDecreaseAllowance(spender, value);
    }
}
