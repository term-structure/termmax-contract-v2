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
    /// @notice Error when the flash loan initiator is not the router itself
    error InvalidFlashLoanInitiator();
    /// @notice Error when the FT amounts withdrawn from vault orders do not equal the repayment amount
    error InvalidFtAmount(uint256 expected, uint256 actual);
    /// @notice Error when the additional asset is neither the market debt token nor collateral token
    error InvalidAdditionalAsset();
}
