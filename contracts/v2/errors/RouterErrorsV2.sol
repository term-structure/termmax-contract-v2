// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface RouterErrorsV2 {
    /// @notice Error when the caller is not the callback address
    error CallbackAddressNotMatch();
    /// @notice Error when the callback is reentrant
    error CallbackReentrant();
    /// @notice Error when the swap path is empty
    error SwapPathsIsEmpty();
    /// @notice Error when rollover fails
    error RolloverFailed(uint256 expectedRepayAmt, uint256 actualRepayAmt);
}
