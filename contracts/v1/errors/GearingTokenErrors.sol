// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface GearingTokenErrors {
    /// @notice Error for merge loans have different owners
    /// @param id The id of Gearing Token has different owner
    /// @param diffOwner The different owner
    error CanNotMergeLoanWithDiffOwner(uint256 id, address diffOwner);
    /// @notice Error for liquidate loan when Gearing Token don't support liquidation
    error GtDoNotSupportLiquidation();
    /// @notice Error for repay the loan after maturity day
    /// @param id The id of Gearing Token
    error GtIsExpired(uint256 id);
    /// @notice Error for liquidate loan when its ltv less than liquidation threshhold
    /// @param id The id of Gearing Token
    error GtIsSafe(uint256 id);
    /// @notice Error for the ltv of loan is bigger than maxium ltv
    /// @param id The id of Gearing Token
    /// @param owner The owner of Gearing Token
    /// @param ltv The loan to value
    error GtIsNotHealthy(uint256 id, address owner, uint128 ltv);
    /// @notice Error for the ltv increase after liquidation
    /// @param id The id of Gearing Token
    /// @param ltvBefore Loan to value before liquidation
    /// @param ltvAfter Loan to value after liquidation
    error LtvIncreasedAfterLiquidation(uint256 id, uint128 ltvBefore, uint128 ltvAfter);
    /// @notice Error for unauthorized operation
    /// @param id The id of Gearing Token
    error CallerIsNotTheOwner(uint256 id);
    /// @notice Error for liquidate the loan with invalid repay amount
    /// @param id The id of Gearing Token
    /// @param repayAmt The id of Gearing Token
    /// @param maxRepayAmt The maxium repay amount when liquidating or repaying
    error RepayAmtExceedsMaxRepayAmt(uint256 id, uint128 repayAmt, uint128 maxRepayAmt);
    /// @notice Error for liquidate the loan after liquidation window
    error CanNotLiquidationAfterFinalDeadline(uint256 id, uint256 liquidationDeadline);
    /// @notice Error for debt value less than minimal limit
    /// @param debtValue The debtValue is USD, decimals 1e8
    error DebtValueIsTooSmall(uint256 debtValue);
    /// @notice Error for unauthorized operation
    /// @param id The id of Gearing Token
    /// @param caller The caller
    error AuthorizationFailed(uint256 id, address caller);
    /**
     * @notice Error thrown when the liquidation LTV is less than the max LTV
     */
    error LiquidationLtvMustBeGreaterThanMaxLtv();
}
