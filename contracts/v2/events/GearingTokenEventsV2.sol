// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Gearing Token Events V2
 * @author Term Structure Labs
 * @notice Interface defining events for Gearing Token operations in TermMax V2 protocol
 */
interface GearingTokenEventsV2 {
    /**
     * @notice Emitted when a new Gearing Token is initialized
     * @dev Fired during the setup of a new gearing token with its market association and metadata
     * @param market The address of the TermMax market associated with this gearing token
     * @param name The human-readable name of the gearing token
     * @param symbol The trading symbol of the gearing token
     * @param initialData Additional initialization data specific to the token setup
     */
    event GearingTokenInitialized(address indexed market, string name, string symbol, bytes initialData);

    /**
     * @notice Emitted when repaying the debt of a Gearing Token
     * @dev Tracks standard debt repayment operations for accounting and monitoring purposes
     * @param id The unique identifier of the Gearing Token position
     * @param repayAmt The amount of debt being repaid (in the debt token denomination)
     * @param byDebtToken True if repaying using debt tokens, false if using bond tokens
     * @param repayAll True if this repayment closes the entire debt position, false for partial repayment
     */
    event Repay(uint256 indexed id, uint256 repayAmt, bool byDebtToken, bool repayAll);

    /**
     * @notice Emitted when repaying debt and removing collateral from a Gearing Token
     * @dev Tracks debt repayment and collateral removal operations for accounting and monitoring purposes
     * @param id The unique identifier of the Gearing Token position
     * @param repayAmt The amount of debt being repaid (uint128 for gas optimization)
     * @param byDebtToken True if repaying using debt tokens, false if using FT tokens
     * @param removedCollateral Encoded data about collateral that was removed
     */
    event RepayAndRemoveCollateral(uint256 indexed id, uint256 repayAmt, bool byDebtToken, bytes removedCollateral);

    /**
     * @notice Emitted when executing a flash repayment operation
     * @dev Flash repay allows atomic debt repayment with collateral removal in a single transaction
     * @param id The unique identifier of the Gearing Token position being repaid
     * @param caller The address that initiated the flash repayment transaction
     * @param repayAmt The amount of debt being repaid (uint128 for gas optimization)
     * @param byDebtToken True if repaying using debt tokens, false if using bond tokens
     * @param repayAll True if this repayment closes the entire debt position, false for partial repayment
     * @param removedCollateral Encoded data about collateral that was removed during the flash repay operation
     */
    event FlashRepay(
        uint256 indexed id,
        address indexed caller,
        uint128 repayAmt,
        bool byDebtToken,
        bool repayAll,
        bytes removedCollateral
    );

    /// @notice Emitted when the collateral capacity is updated
    event CollateralCapacityUpdated(uint256 newCapacity);
}
