// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Vault Events V2 Interface
 * @notice Additional events for TermMax vault V2 operations
 */
interface VaultEventsV2 {
    /**
     * @notice Emitted when a new minimum APY is proposed
     * @param newMinApy The proposed minimum APY
     * @param validAt The timestamp when the minimum APY change will take effect
     */
    event SubmitMinApy(uint64 newMinApy, uint64 validAt);

    /**
     * @notice Emitted when the minimum APY is updated
     * @param caller The address that updated the minimum APY
     * @param newMinApy The new minimum APY value
     */
    event SetMinApy(address indexed caller, uint64 newMinApy);

    /**
     * @notice Emitted when a new minimum idle fund rate is proposed
     * @param newMinIdleFundRate The proposed minimum idle fund rate
     * @param validAt The timestamp when the minimum idle fund rate change will take effect
     */
    event SubmitMinIdleFundRate(uint64 newMinIdleFundRate, uint64 validAt);

    /**
     * @notice Emitted when the minimum idle fund rate is updated
     * @param caller The address that updated the minimum idle fund rate
     * @param newMinIdleFundRate The new minimum idle fund rate value
     */
    event SetMinIdleFundRate(address indexed caller, uint64 newMinIdleFundRate);

    /**
     * @notice Emitted when a pending minimum APY change is revoked
     * @param caller The address that initiated the revocation
     */
    event RevokePendingMinApy(address indexed caller);

    /**
     * @notice Emitted when a pending minimum idle fund rate change is revoked
     * @param caller The address that initiated the revocation
     */
    event RevokePendingMinIdleFundRate(address indexed caller);

    /**
     * @notice Emitted when accrued interest is calculated
     * @param newAccretingPrincipal The updated accreting principal
     * @param newPerformanceFee The updated performance fee
     */
    event AccruedInterest(uint256 newAccretingPrincipal, uint256 newPerformanceFee);
}
