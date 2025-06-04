// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CurveCuts} from "../storage/TermMaxStorage.sol";

/**
 * @title Vault Events Interface
 * @notice Events emitted by the TermMax vault operations
 */
interface VaultEvents {
    /**
     * @notice Emitted when a new guardian is proposed
     * @param newGuardian The address of the proposed guardian
     * @param validAt The timestamp when the guardian change will take effect
     */
    event SubmitGuardian(address newGuardian, uint64 validAt);

    /**
     * @notice Emitted when the vault capacity is updated
     * @param caller The address that initiated the capacity update
     * @param newCapacity The new capacity value
     */
    event SetCapacity(address indexed caller, uint256 newCapacity);

    /**
     * @notice Emitted when a new curator is set
     * @param newCurator The address of the new curator
     */
    event SetCurator(address newCurator);

    /**
     * @notice Emitted when a market's whitelist status is proposed
     * @param market The address of the market
     * @param validAt The timestamp when the market whitelist change will take effect
     */
    event SubmitMarketToWhitelist(address indexed market, uint64 validAt);

    /**
     * @notice Emitted when a pending market whitelist change is revoked
     * @param caller The address that initiated the revocation
     * @param market The address of the market
     */
    event RevokePendingMarket(address indexed caller, address indexed market);

    /**
     * @notice Emitted when the performance fee rate is updated
     * @param caller The address that initiated the update
     * @param newPerformanceFeeRate The new performance fee rate
     */
    event SetPerformanceFeeRate(address indexed caller, uint256 newPerformanceFeeRate);

    /**
     * @notice Emitted when a new performance fee rate is proposed
     * @param newPerformanceFeeRate The proposed performance fee rate
     * @param validAt The timestamp when the performance fee rate change will take effect
     */
    event SubmitPerformanceFeeRate(uint256 newPerformanceFeeRate, uint64 validAt);

    /**
     * @notice Emitted when a market's whitelist status is updated
     * @param caller The address that initiated the update
     * @param market The address of the market
     * @param isWhitelisted The new whitelist status
     */
    event SetMarketWhitelist(address indexed caller, address indexed market, bool isWhitelisted);

    /**
     * @notice Emitted when a new order is created
     * @param caller The address that created the order
     * @param market The market address
     * @param order The order address
     * @param maxSupply The maximum supply for the order
     * @param initialReserve The initial reserve amount
     * @param curveCuts The curve parameters for the order
     */
    event CreateOrder(
        address indexed caller,
        address indexed market,
        address indexed order,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts curveCuts
    );

    /**
     * @notice Emitted when an order is updated
     * @param caller The address that updated the order
     * @param order The order address
     * @param changes The changes made to the order
     * @param maxSupply The new maximum supply for the order
     * @param curveCuts The updated curve parameters for the order
     */
    event UpdateOrder(
        address indexed caller, address indexed order, int256 changes, uint256 maxSupply, CurveCuts curveCuts
    );

    /**
     * @notice Emitted when bad debt is dealt with
     * @param caller The address that initiated the bad debt deal
     * @param recipient The address that received the bad debt
     * @param collateral The collateral address
     * @param badDebt The amount of bad debt
     * @param shares The number of shares
     * @param collateralOut The amount of collateral out
     */
    event DealBadDebt(
        address indexed caller,
        address indexed recipient,
        address indexed collateral,
        uint256 badDebt,
        uint256 shares,
        uint256 collateralOut
    );

    /**
     * @notice Emitted when an order is redeemed
     * @param caller The address that redeemed the order
     * @param order The order address
     * @param ftAmt The amount of ft tokens
     * @param redeemedAmt The amount redeemed
     */
    event RedeemOrder(address indexed caller, address indexed order, uint128 ftAmt, uint128 redeemedAmt);

    /**
     * @notice Emitted when performance fee is withdrawn
     * @param caller The address that withdrew the performance fee
     * @param recipient The address that received the performance fee
     * @param amount The amount of performance fee withdrawn
     */
    event WithdrawPerformanceFee(address indexed caller, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a new timelock is proposed
     * @param newTimelock The proposed timelock value
     * @param validAt The timestamp when the timelock change will take effect
     */
    event SubmitTimelock(uint256 newTimelock, uint64 validAt);

    /**
     * @notice Emitted when the timelock is updated
     * @param caller The address that updated the timelock
     * @param newTimelock The new timelock value
     */
    event SetTimelock(address indexed caller, uint256 newTimelock);

    /**
     * @notice Emitted when the guardian is updated
     * @param caller The address that updated the guardian
     * @param newGuardian The new guardian address
     */
    event SetGuardian(address indexed caller, address newGuardian);

    /**
     * @notice Emitted when a pending timelock change is revoked
     * @param caller The address that initiated the revocation
     */
    event RevokePendingTimelock(address indexed caller);

    /**
     * @notice Emitted when a pending guardian change is revoked
     * @param caller The address that initiated the revocation
     */
    event RevokePendingGuardian(address indexed caller);

    /**
     * @notice Emitted when the performance fee rate is proposed to be revoked
     * @param caller The address that initiated the revocation
     */
    event RevokePendingPerformanceFeeRate(address indexed caller);

    /**
     * @notice Emitted when the cap for an order is updated
     * @param caller The address that updated the cap
     * @param order The order address
     * @param newCap The new cap value
     */
    event SetCap(address indexed caller, address indexed order, uint256 newCap);

    /**
     * @notice Emitted when an allocator's status is updated
     * @param allocator The allocator address
     * @param newIsAllocator The new allocator status
     */
    event SetIsAllocator(address indexed allocator, bool newIsAllocator);

    /**
     * @notice Emitted when the supply queue is updated
     * @param caller The address that updated the supply queue
     * @param newSupplyQueue The new supply queue
     */
    event UpdateSupplyQueue(address indexed caller, address[] newSupplyQueue);

    /**
     * @notice Emitted when the withdraw queue is updated
     * @param caller The address that updated the withdraw queue
     * @param newWithdrawQueue The new withdraw queue
     */
    event UpdateWithdrawQueue(address indexed caller, address[] newWithdrawQueue);
}
