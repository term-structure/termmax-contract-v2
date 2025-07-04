// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TransferUtilsV2} from "../../../v2/lib/TransferUtilsV2.sol";
import {ISwapAdapter} from "../ISwapAdapter.sol";
import {OnlyProxyCall} from "../../../v2/lib/OnlyProxyCall.sol";

/**
 * @title TermMax ERC20SwapAdapter V2
 * @author Term Structure Labs
 * @notice This contract is an abstract base for ERC20 swap adapters in the TermMax protocol.
 */
abstract contract ERC20SwapAdapterV2 is ISwapAdapter, OnlyProxyCall {
    using TransferUtilsV2 for IERC20;

    /// @notice Error for less than min token out
    /// @dev Revert when the actual output token amount is less than the expected minimum
    error LessThanMinTokenOut(uint256 actual, uint256 expected);
    /// @notice Error for exceeding max token in
    /// @dev Revert when the actual required input token amount exceeds the expected maximum
    error ExceedMaxTokenIn(uint256 actual, uint256 expected);

    /**
     * @inheritdoc ISwapAdapter
     */
    function swap(address tokenIn, address tokenOut, bytes memory tokenInAmt, bytes memory swapData)
        external
        override
        onlyProxy
        returns (bytes memory)
    {
        return abi.encode(_swap(IERC20(tokenIn), IERC20(tokenOut), abi.decode(tokenInAmt, (uint256)), swapData));
    }

    function _swap(IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        returns (uint256 tokenOutAmt);

    /**
     * @inheritdoc ISwapAdapter
     */
    function approveOutputToken(address token, address spender, bytes memory tokenData) external override {
        IERC20(token).safeIncreaseAllowance(spender, _decodeAmount(tokenData));
    }

    /**
     * @inheritdoc ISwapAdapter
     */
    function transferOutputToken(address token, address to, bytes memory tokenData) external override {
        IERC20(token).safeTransfer(to, _decodeAmount(tokenData));
    }

    /**
     * @inheritdoc ISwapAdapter
     */
    function transferInputTokenFrom(address token, address from, address to, bytes memory tokenData)
        external
        override
    {
        IERC20(token).safeTransferFrom(from, to, _decodeAmount(tokenData));
    }

    /// @notice Encode uin256 to bytes
    function _encodeAmount(uint256 amount) internal pure returns (bytes memory data) {
        data = abi.encode(amount);
    }

    /// @notice Decode uin256 from bytes
    function _decodeAmount(bytes memory data) internal pure returns (uint256 amount) {
        amount = abi.decode(data, (uint256));
    }
}
