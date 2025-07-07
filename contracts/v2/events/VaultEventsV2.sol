// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Vault Events V2 Interface
 * @notice Additional events for TermMax vault V2 operations
 */
interface VaultEventsV2 {
    event SetPoolWhitelist(address indexed caller, address indexed pool, bool isWhitelisted);
    event SubmitPoolToWhitelist(address indexed pool, uint64 validAt);

    /**
     * @notice Emitted when an order is redeemed
     * @param caller The address that redeemed the order
     * @param order The order address
     * @param badDebt The amount of bad debt associated with the order
     * @param diliveryAmount The amount of collateral delivered to the vault
     */
    event RedeemOrder(address indexed caller, address indexed order, uint256 badDebt, uint256 diliveryAmount);

    /**
     * @notice Emitted when a new order is created
     * @param caller The address of the caller
     * @param market The address of the market
     * @param order The address of the new order
     */
    event NewOrderCreated(address indexed caller, address indexed market, address indexed order);

    /**
     * @notice Emitted when updating the order curves
     * @param caller The operator who updated the order curves
     * @param orders The addresses of the orders that were updated
     */
    event UpdateOrderCurve(address indexed caller, address[] orders);

    /**
     * @notice Emitted when an order's pool is updated
     * @param caller The operator who updated the order's pool
     * @param orders The addresses of the orders that were updated
     */
    event UpdateOrderPools(address indexed caller, address[] orders);

    /**
     * @notice Emitted when an order's configuration is updated
     * @param caller The operator who updated the order configuration
     * @param orders The addresses of the orders that were updated
     */
    event UpdateOrderConfiguration(address indexed caller, address[] orders);

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
