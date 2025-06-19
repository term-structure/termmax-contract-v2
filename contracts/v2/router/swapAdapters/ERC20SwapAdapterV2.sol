// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferUtilsV2} from "../../lib/TransferUtilsV2.sol";
import {IERC20SwapAdapter} from "../IERC20SwapAdapter.sol";
import {OnlyProxyCall} from "../../lib/OnlyProxyCall.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title TermMax ERC20SwapAdapter V2
 * @author Term Structure Labs
 * @notice This contract is an abstract base for ERC20 swap adapters in the TermMax protocol.
 */
abstract contract ERC20SwapAdapterV2 is IERC20SwapAdapter, OnlyProxyCall {
    using TransferUtilsV2 for IERC20;

    /// @notice Error for less than min token out
    /// @dev Revert when the actual output token amount is less than the expected minimum
    error LessThanMinTokenOut(uint256 actual, uint256 expected);
    /// @notice Error for exceeding max token in
    /// @dev Revert when the actual required input token amount exceeds the expected maximum
    error ExceedMaxTokenIn(uint256 actual, uint256 expected);

    /**
     * @inheritdoc IERC20SwapAdapter
     */
    function swap(address receipient, address tokenIn, address tokenOut, uint256 tokenInAmt, bytes memory swapData)
        external
        override
        onlyProxy
        returns (uint256)
    {
        return _swap(receipient, IERC20(tokenIn), IERC20(tokenOut), tokenInAmt, swapData);
    }

    function _swap(address receipient, IERC20 tokenIn, IERC20 tokenOut, uint256 tokenInAmt, bytes memory swapData)
        internal
        virtual
        returns (uint256 tokenOutAmt)
    {}
}
