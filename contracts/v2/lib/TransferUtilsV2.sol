// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library TransferUtilsV2 {
    using SafeERC20 for IERC20;

    error CanNotTransferUintMax();

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        token.safeTransferFrom(from, to, value);
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        token.safeTransfer(to, value);
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        token.safeIncreaseAllowance(spender, value);
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        if (value == 0 || spender == address(this)) {
            return;
        }
        token.safeDecreaseAllowance(spender, value);
    }

    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        token.forceApprove(spender, value);
    }

    function safeTransferFromWithCheck(IERC20 token, address from, address to, uint256 value) internal {
        if (from == to || value == 0) {
            return;
        }
        token.safeTransferFrom(from, to, value);
    }

    function safeTransferWithCheck(IERC20 token, address to, uint256 value) internal {
        if (to == address(this) || value == 0) {
            return;
        }
        token.safeTransfer(to, value);
    }

    function safeIncreaseAllowanceWithCheck(IERC20 token, address spender, uint256 value) internal {
        if (value == 0 || spender == address(this)) {
            return;
        }
        token.safeIncreaseAllowance(spender, value);
    }

    function safeDecreaseAllowanceWithCheck(IERC20 token, address spender, uint256 value) internal {
        if (value == 0 || spender == address(this)) {
            return;
        }
        token.safeDecreaseAllowance(spender, value);
    }

    function forceApproveWithCheck(IERC20 token, address spender, uint256 value) internal {
        if (spender == address(this)) {
            return;
        }
        token.forceApprove(spender, value);
    }
}
