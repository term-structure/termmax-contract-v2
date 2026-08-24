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
    /// @notice Error when the ft sale proceeds are not sent back to the router to repay the flash loan
    error InvalidSwapRecipient();
    /// @notice Error when the third party lending market is not quoted in the new market's token pair
    error LendingMarketTokensNotMatch();
    /// @notice Error when more collateral is asked to be moved than the position holds
    error CollateralAmtExceedsPosition(uint256 positionCollateral, uint256 collateralAmt);
    /// @notice Error when the debt token the flash loan repayment does not need is worth at least
    ///         the whole debt of the new position, which would close it instead of rolling it
    error SurplusExceedsNewDebt(uint256 newDebtAmt, uint256 surplus);
    /// @notice Error when the flash lender returned without ever running the rollover
    error RolloverNotExecuted();
    /// @notice Error when the aave supply position is not fully unwound into its underlying collateral
    error ATokenNotFullyWithdrawn();
    /// @notice Error when the delegation signature does not delegate the caller's own position to the router
    error InvalidDelegation();
}
