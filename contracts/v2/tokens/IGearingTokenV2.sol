// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title TermMax Gearing token interface V2
 * @author Term Structure Labs
 */
interface IGearingTokenV2 {
    /// @notice Repay the debt of Gearing Token,
    ///         The borrower can repay the debt after receiving the collateral
    /// @param id The id of Gearing Token
    /// @param byDebtToken Repay using debtToken token or bonds token
    /// @param repayAmt The amount of debt you want to repay
    /// @param removedCollateral The collateral data to be removed
    /// @param callbackData The data to be passed to the callback function
    /// @return repayAll Whether the repayment is complete
    function flashRepay(
        uint256 id,
        uint128 repayAmt,
        bool byDebtToken,
        bytes memory removedCollateral,
        bytes calldata callbackData
    ) external returns (bool repayAll);
}
