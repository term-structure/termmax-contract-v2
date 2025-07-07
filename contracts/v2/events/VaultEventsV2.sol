// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Vault Events V2 Interface
 * @notice Additional events for TermMax vault V2 operations
 * @dev This interface defines events emitted by the TermMax Vault V2 contract for:
 *      - Pool whitelist management with timelock mechanism
 *      - Order lifecycle management (creation, redemption, configuration updates)
 *      - APY and idle fund rate parameter changes with timelock approval
 *      - Interest accrual and performance fee calculations
 *
 *      Events are organized into logical groups for easier tracking and monitoring
 *      of vault operations and governance activities.
 */
interface VaultEventsV2 {
    // ============================================
    // POOL WHITELIST MANAGEMENT EVENTS
    // ============================================

    /**
     * @notice Emitted when a pending pool whitelist change is revoked
     * @dev This event is fired when governance cancels a proposed pool whitelist change
     *      before the timelock period expires, preventing the change from taking effect.
     * @param caller The address that initiated the revocation (typically governance)
     * @param pool The address of the pool whose pending whitelist change was revoked
     */
    event RevokePendingPool(address indexed caller, address indexed pool);

    /**
     * @notice Emitted when a pool's whitelist status is successfully updated
     * @dev This event is fired when a pool is added to or removed from the whitelist
     *      after the timelock period has elapsed and the change is accepted.
     * @param caller The address that executed the whitelist change (typically governance)
     * @param pool The address of the pool whose whitelist status was updated
     * @param isWhitelisted True if the pool was added to whitelist, false if removed
     */
    event SetPoolWhitelist(address indexed caller, address indexed pool, bool isWhitelisted);

    /**
     * @notice Emitted when a pool whitelist change is submitted for timelock approval
     * @dev This event is fired when governance proposes to add or remove a pool from
     *      the whitelist, initiating the timelock period for security.
     * @param pool The address of the pool proposed for whitelist status change
     * @param validAt The timestamp when the whitelist change will become valid and can be executed
     */
    event SubmitPoolToWhitelist(address indexed pool, uint64 validAt);

    // ============================================
    // ORDER LIFECYCLE EVENTS
    // ============================================

    /**
     * @notice Emitted when an order is redeemed and settled
     * @dev This event tracks the redemption of orders, including any bad debt that occurred
     *      and the actual collateral amount delivered back to the vault.
     * @param caller The address that initiated the order redemption
     * @param order The address of the order contract being redeemed
     * @param badDebt The amount of bad debt associated with the order (losses not covered by collateral)
     * @param diliveryAmount The amount of collateral successfully delivered back to the vault
     */
    event RedeemOrder(address indexed caller, address indexed order, uint256 badDebt, uint256 diliveryAmount);

    /**
     * @notice Emitted when a new order is successfully created and deployed
     * @dev This event tracks the creation of new TermMax orders within the vault system,
     *      linking them to their associated market for monitoring and management.
     * @param caller The address that initiated the order creation (typically vault operator)
     * @param market The address of the TermMax market where the order will operate
     * @param order The address of the newly deployed order contract
     */
    event NewOrderCreated(address indexed caller, address indexed market, address indexed order);

    // ============================================
    // ORDER CONFIGURATION UPDATE EVENTS
    // ============================================

    /**
     * @notice Emitted when order curve configurations are updated
     * @dev This event tracks batch updates to order pricing curves, which affect
     *      how orders price trades and distribute liquidity across different price levels.
     * @param caller The operator who executed the curve updates (typically vault management)
     * @param orders The addresses of all orders whose curves were updated in this transaction
     */
    event UpdateOrderCurve(address indexed caller, address[] orders);

    /**
     * @notice Emitted when order pool assignments are updated
     * @dev This event tracks changes to which ERC4626 pools orders are connected to,
     *      affecting where order collateral is deployed for yield generation.
     * @param caller The operator who executed the pool updates (typically vault management)
     * @param orders The addresses of all orders whose pool assignments were updated
     */
    event UpdateOrderPools(address indexed caller, address[] orders);

    /**
     * @notice Emitted when order configurations are updated
     * @dev This event tracks batch updates to order parameters including liquidity settings,
     *      fee structures, risk parameters, and other operational configurations.
     * @param caller The operator who executed the configuration updates (typically vault management)
     * @param orders The addresses of all orders whose configurations were updated
     */
    event UpdateOrderConfiguration(address indexed caller, address[] orders);

    // ============================================
    // APY MANAGEMENT EVENTS
    // ============================================

    /**
     * @notice Emitted when a new minimum APY is proposed for timelock approval
     * @dev This event initiates the governance process for changing the vault's minimum APY,
     *      starting the timelock period to allow for community review and feedback.
     * @param newMinApy The proposed minimum APY value (e.g., 5% APY = 0.05e8)
     * @param validAt The timestamp when the minimum APY change will become valid and executable
     */
    event SubmitMinApy(uint64 newMinApy, uint64 validAt);

    /**
     * @notice Emitted when the minimum APY is successfully updated
     * @dev This event confirms that a proposed minimum APY change has been accepted
     *      and applied after the timelock period elapsed.
     * @param caller The address that executed the APY update (typically governance)
     * @param newMinApy The new minimum APY value that is now active
     */
    event SetMinApy(address indexed caller, uint64 newMinApy);

    /**
     * @notice Emitted when a pending minimum APY change is revoked
     * @dev This event is fired when governance cancels a proposed minimum APY change
     *      before the timelock expires, preventing the change from taking effect.
     * @param caller The address that initiated the revocation (typically governance)
     */
    event RevokePendingMinApy(address indexed caller);

    // ============================================
    // IDLE FUND RATE MANAGEMENT EVENTS
    // ============================================

    /**
     * @notice Emitted when a new minimum idle fund rate is proposed for timelock approval
     * @dev This event initiates the governance process for changing the rate applied to
     *      idle vault funds, starting the timelock period for security.
     * @param newMinIdleFundRate The proposed minimum idle fund rate (e.g., 10% rate = 0.10e8)
     * @param validAt The timestamp when the rate change will become valid and executable
     */
    event SubmitMinIdleFundRate(uint64 newMinIdleFundRate, uint64 validAt);

    /**
     * @notice Emitted when the minimum idle fund rate is successfully updated
     * @dev This event confirms that a proposed idle fund rate change has been accepted
     *      and applied after the timelock period elapsed.
     * @param caller The address that executed the rate update (typically governance)
     * @param newMinIdleFundRate The new minimum idle fund rate value that is now active
     */
    event SetMinIdleFundRate(address indexed caller, uint64 newMinIdleFundRate);

    /**
     * @notice Emitted when a pending minimum idle fund rate change is revoked
     * @dev This event is fired when governance cancels a proposed idle fund rate change
     *      before the timelock expires, preventing the change from taking effect.
     * @param caller The address that initiated the revocation (typically governance)
     */
    event RevokePendingMinIdleFundRate(address indexed caller);

    // ============================================
    // INTEREST AND FEE EVENTS
    // ============================================

    /**
     * @notice Emitted when interest is accrued and performance fees are calculated
     * @dev This event tracks the vault's interest accrual process, showing how the
     *      accreting principal grows over time and performance fees are calculated.
     *      This is typically emitted during deposit/withdrawal operations or periodic updates.
     * @param newAccretingPrincipal The updated total accreting principal after interest accrual
     * @param newPerformanceFee The updated accumulated performance fee amount
     */
    event AccruedInterest(uint256 newAccretingPrincipal, uint256 newPerformanceFee);
}
