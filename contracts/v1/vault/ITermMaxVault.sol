// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts, VaultInitialParams} from "../storage/TermMaxStorage.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {OrderInfo} from "./VaultStorage.sol";

/**
 * @title TermMax Vault Interface
 * @author Term Structure Labs
 * @notice Interface for TermMax vaults that extends the ERC4626 standard
 * @dev Implements ERC4626 tokenized vault standard with additional TermMax-specific functionality
 */
interface ITermMaxVault is IERC4626 {
    /**
     * @notice Initializes the vault
     * @param params The initial parameters of the vault
     */
    function initialize(VaultInitialParams memory params) external;

    /**
     * @notice Handles bad debt by exchanging shares for collateral
     * @param collaretal The collateral token address
     * @param badDebtAmt The amount of bad debt to handle
     * @param recipient The recipient of the collateral
     * @param owner The owner of the shares
     * @return shares The amount of shares burned
     * @return collaretalOut The amount of collateral released
     */
    function dealBadDebt(address collaretal, uint256 badDebtAmt, address recipient, address owner)
        external
        returns (uint256 shares, uint256 collaretalOut);

    /**
     * @notice Returns the current Annual Percentage Rate (APR)
     * @return The current APR as a percentage with 8 decimals
     */
    function apr() external view returns (uint256);

    /**
     * @notice Returns the guardian address
     * @return The address of the guardian
     */
    function guardian() external view returns (address);

    /**
     * @notice Returns the curator address
     * @return The address of the curator
     */
    function curator() external view returns (address);

    /**
     * @notice Checks if an address is an allocator
     * @param allocator The address to check
     * @return True if the address is an allocator, false otherwise
     */
    function isAllocator(address allocator) external view returns (bool);

    /**
     * @notice Checks if a market is whitelisted
     * @param market The market address to check
     * @return True if the market is whitelisted, false otherwise
     */
    function marketWhitelist(address market) external view returns (bool);

    /**
     * @notice Returns the timelock duration
     * @return The timelock duration in seconds
     */
    function timelock() external view returns (uint256);

    /**
     * @notice Returns the pending market information
     * @param market The market address to check
     */
    function pendingMarkets(address market) external view returns (PendingUint192 memory);

    /**
     * @notice Returns the pending timelock information
     */
    function pendingTimelock() external view returns (PendingUint192 memory);

    /**
     * @notice Returns the pending performance fee rate information
     */
    function pendingPerformanceFeeRate() external view returns (PendingUint192 memory);

    /**
     * @notice Returns the pending guardian information
     */
    function pendingGuardian() external view returns (PendingAddress memory);

    /**
     * @notice Returns the performance fee rate
     * @return The performance fee rate as a percentage with 18 decimals
     */
    function performanceFeeRate() external view returns (uint64);

    /**
     * @notice Returns the total amount of ft tokens
     * @return The total amount of ft tokens
     */
    function totalFt() external view returns (uint256);

    /**
     * @notice Returns the accreting principal amount
     * @return The accreting principal amount
     */
    function accretingPrincipal() external view returns (uint256);

    /**
     * @notice Returns the annualized interest
     * @return The annualized interest
     */
    function annualizedInterest() external view returns (uint256);

    /**
     * @notice Returns the performance fee amount
     * @return The performance fee amount
     */
    function performanceFee() external view returns (uint256);

    /**
     * @notice Returns the supply queue information
     * @param index The index of the supply queue to retrieve
     * @return The address of the supply queue at the specified index
     */
    function supplyQueue(uint256 index) external view returns (address);

    /**
     * @notice Returns the withdraw queue information
     * @param index The index of the withdraw queue to retrieve
     * @return The address of the withdraw queue at the specified index
     */
    function withdrawQueue(uint256 index) external view returns (address);

    /// @notice Return the length of the supply queue
    function supplyQueueLength() external view returns (uint256);

    /// @notice Return the length of the withdraw queue
    function withdrawQueueLength() external view returns (uint256);

    /**
     * @notice Returns the order mapping information
     * @param order The order address to retrieve
     */
    function orderMapping(address order) external view returns (OrderInfo memory);

    /**
     * @notice Returns the bad debt mapping information
     * @param collateral The collateral address to retrieve
     * @return The bad debt amount associated with the collateral
     */
    function badDebtMapping(address collateral) external view returns (uint256);

    /**
     * @notice Creates a new order
     * @param market The market address to create the order for
     * @param maxSupply The maximum supply of the order
     * @param initialReserve The initial reserve amount of the order
     * @param curveCuts The curve cuts to use for the order
     * @return order The newly created order
     */
    function createOrder(ITermMaxMarket market, uint256 maxSupply, uint256 initialReserve, CurveCuts calldata curveCuts)
        external
        returns (ITermMaxOrder order);

    /**
     * @notice Updates multiple orders
     * @param orders The orders to update
     * @param changes The changes to apply to each order
     * @param maxSupplies The maximum supplies to update for each order
     * @param curveCuts The curve cuts to update for each order
     */
    function updateOrders(
        ITermMaxOrder[] calldata orders,
        int256[] calldata changes,
        uint256[] calldata maxSupplies,
        CurveCuts[] calldata curveCuts
    ) external;

    /**
     * @notice Updates the supply queue
     * @param indexes The indexes to update in the supply queue
     */
    function updateSupplyQueue(uint256[] calldata indexes) external;

    /**
     * @notice Updates the withdraw queue
     * @param indexes The indexes to update in the withdraw queue
     */
    function updateWithdrawQueue(uint256[] calldata indexes) external;

    /**
     * @notice Redeems an order
     * @param order The order to redeem
     */
    function redeemOrder(ITermMaxOrder order) external;

    /**
     * @notice Withdraws performance fee
     * @param recipient The recipient of the performance fee
     * @param amount The amount of performance fee to withdraw
     */
    function withdrawPerformanceFee(address recipient, uint256 amount) external;

    /**
     * @notice Submits a new guardian address
     * @param newGuardian The new guardian address
     */
    function submitGuardian(address newGuardian) external;

    /**
     * @notice Sets a new curator address
     * @param newCurator The new curator address
     */
    function setCurator(address newCurator) external;

    /**
     * @notice Submits a new timelock duration
     * @param newTimelock The new timelock duration
     */
    function submitTimelock(uint256 newTimelock) external;

    /**
     * @notice Sets a new capacity
     * @param newCapacity The new capacity
     */
    function setCapacity(uint256 newCapacity) external;

    /**
     * @notice Sets whether an address is an allocator
     * @param newAllocator The address to set as an allocator
     * @param newIsAllocator Whether the address is an allocator
     */
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    /**
     * @notice Submits a new performance fee rate
     * @param newPerformanceFeeRate The new performance fee rate
     */
    function submitPerformanceFeeRate(uint184 newPerformanceFeeRate) external;

    /**
     * @notice Submits a new market for whitelisting
     * @param market The market address to whitelist
     * @param isWhitelisted Whether the market is whitelisted
     */
    function submitMarket(address market, bool isWhitelisted) external;

    /**
     * @notice Revokes the pending timelock
     */
    function revokePendingTimelock() external;

    /**
     * @notice Revokes the pending guardian
     */
    function revokePendingGuardian() external;

    /**
     * @notice Revokes the pending market
     * @param market The market address to revoke
     */
    function revokePendingMarket(address market) external;

    /**
     * @notice Revokes the pending performance fee rate
     */
    function revokePendingPerformanceFeeRate() external;

    /**
     * @notice Accepts the pending timelock
     */
    function acceptTimelock() external;

    /**
     * @notice Accepts the pending guardian
     */
    function acceptGuardian() external;

    /**
     * @notice Accepts the pending market
     * @param market The market address to accept
     */
    function acceptMarket(address market) external;

    /**
     * @notice Accepts the pending performance fee rate
     */
    function acceptPerformanceFeeRate() external;
}
