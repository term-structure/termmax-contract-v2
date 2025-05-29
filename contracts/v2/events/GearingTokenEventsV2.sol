// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface GearingTokenEventsV2 {
    /// @notice Emitted when a new Gearing Token is initialized
    event GearingTokenInitialized(address indexed market, string name, string symbol, bytes initialData);

    /// @notice Emitted when repaying the debt of Gearing Token
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt repaid
    /// @param byDebtToken Repay using debtToken token or bonds token
    /// @param repayAll Repay all the debt
    event Repay(uint256 indexed id, uint256 repayAmt, bool byDebtToken, bool repayAll);

    event FlashRepay(
        uint256 indexed id,
        address indexed caller,
        uint128 repayAmt,
        bool byDebtToken,
        bool repayAll,
        bytes removedCollateral
    );
}
