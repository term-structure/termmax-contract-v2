// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TransferUtilsV2} from "../../lib/TransferUtilsV2.sol";
import {IERC20SwapAdapter} from "../IERC20SwapAdapter.sol";
import {ERC20SwapAdapter as ERC20SwapAdapterV1} from "../../../v1/router/swapAdapters/ERC20SwapAdapter.sol";
import {OnlyProxyCall} from "../../lib/OnlyProxyCall.sol";

/**
 * @title TermMax ERC20SwapAdapter V2
 * @author Term Structure Labs
 * @notice This contract is an abstract base for ERC20 swap adapters in the TermMax protocol.
 */
abstract contract ERC20SwapAdapterV2 is IERC20SwapAdapter, OnlyProxyCall, ERC20SwapAdapterV1 {
    using TransferUtilsV2 for IERC20;

    /// @notice Error for exceeding max token in
    /// @dev Revert when the actual required input token amount exceeds the expected maximum
    error ExceedMaxTokenIn(uint256 actual, uint256 expected);
    /// @notice Error for zero address refund
    error RefundAddressIsZeroAddress();
    /// @notice Error for invalid selector-encoded calldata
    error InvalidSelectorData();
    /// @notice Error for selectors that are not allowed by the adapter
    error SelectorNotWhitelisted(bytes4 selector);

    function selectorWhitelist(bytes4 selector) public pure virtual returns (bool) {
        return _isSelectorWhitelisted(selector);
    }

    function _isSelectorWhitelisted(bytes4) internal pure virtual returns (bool) {
        return false;
    }

    function _validateSelector(bytes memory data) internal pure {
        if (data.length < 4) {
            revert InvalidSelectorData();
        }

        bytes4 selector;
        assembly {
            selector := mload(add(data, 0x20))
        }

        if (!_isSelectorWhitelisted(selector)) {
            revert SelectorNotWhitelisted(selector);
        }
    }

    /**
     * @inheritdoc IERC20SwapAdapter
     */
    function swap(address recipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        override
        onlyProxy
        returns (uint256)
    {
        return _swap(recipient, IERC20(tokenIn), IERC20(tokenOut), tokenInAmt, swapData);
    }

    function _swap(address recipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        returns (uint256 tokenOutAmt);

    /**
     * @inheritdoc ERC20SwapAdapterV1
     */
    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        override
        onlyProxy
        returns (uint256 tokenOutAmt)
    {
        // using address(this) as recipient since this function is only used for router V1
        tokenOutAmt = _swap(address(this), tokenIn, tokenOut, tokenInAmt, swapData);
    }

    function _refund(address recipient, IERC20 token, uint256 amount) internal {
        if (recipient == address(0)) {
            revert RefundAddressIsZeroAddress();
        }
        if (recipient != address(this)) {
            token.safeTransfer(recipient, amount);
        }
    }
}
