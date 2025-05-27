// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface GearingTokenEvents {
    /// @notice Emitted when updating the configuration
    event UpdateConfig(bytes configData);

    /// @notice Emitted when Debt is augmented
    /// @param id The id of Gearing Token
    /// @param ftAmt The amount of debt augmented
    event AugmentDebt(uint256 indexed id, uint256 ftAmt);

    /// @notice Emitted when merging multiple Gearing Tokens into one
    /// @param owner The owner of those tokens
    /// @param newId The id of new Gearing Token
    /// @param ids The array of Gearing Tokens id were merged
    event MergeGts(address indexed owner, uint256 indexed newId, uint256[] ids);

    /// @notice Emitted when removing collateral from the loan
    /// @param id The id of Gearing Token
    /// @param newCollateralData Collateral data after removal
    event RemoveCollateral(uint256 indexed id, bytes newCollateralData);

    /// @notice Emitted when adding collateral to the loan
    /// @param id The id of Gearing Token
    /// @param newCollateralData Collateral data after additional
    event AddCollateral(uint256 indexed id, bytes newCollateralData);

    /// @notice Emitted when repaying the debt of Gearing Token
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt repaid
    /// @param byDebtToken Repay using debtToken token or bonds token
    event Repay(uint256 indexed id, uint256 repayAmt, bool byDebtToken);

    /// @notice Emitted when liquidating Gearing Token
    /// @param id The id of Gearing Token
    /// @param liquidator The liquidator
    /// @param repayAmt The amount of debt liquidated
    /// @param cToLiquidator Collateral data assigned to liquidator
    /// @param cToTreasurer Collateral data assigned to protocol
    /// @param remainningC Remainning collateral data
    event Liquidate(
        uint256 indexed id,
        address indexed liquidator,
        uint128 repayAmt,
        bool byDebtToken,
        bytes cToLiquidator,
        bytes cToTreasurer,
        bytes remainningC
    );
}
