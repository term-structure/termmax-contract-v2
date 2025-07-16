// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {PendingAddress, PendingUint192} from "../../v1/lib/PendingLib.sol";
import {VaultInitialParamsV2} from "../storage/TermMaxStorageV2.sol";
import {CurveCuts} from "../../v1/storage/TermMaxStorage.sol";
import {OrderV2ConfigurationParams} from "./VaultStorageV2.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {ITermMaxOrderV2} from "../ITermMaxOrderV2.sol";

/**
 * @title ITermMaxVaultV2
 * @notice Interface for TermMax Vault V2 contract
 * @dev This interface defines the core functionality for vault operations including:
 *      - Vault initialization and configuration
 *      - APY and idle fund rate management with timelock mechanism
 *      - Pool whitelist management with pending approval system
 *      - Order creation and management (curves, configuration, liquidity)
 *      - Integration with ERC4626 pools and TermMax markets
 *
 *      The vault implements a timelock mechanism for critical parameter changes
 *      to ensure security and allow for community review of proposed changes.
 */
interface ITermMaxVaultV2 {
    // ============================================
    // INITIALIZATION
    // ============================================

    /**
     * @notice Initializes the vault with the provided parameters
     * @dev This function should only be called once during contract deployment.
     *      Sets up initial vault configuration including APY parameters, access controls,
     *      and initial pool configurations.
     * @param params The initial configuration parameters for the vault including:
     *               - minApy: minimum guaranteed APY
     *               - minIdleFundRate: minimum rate for idle funds
     *               - governance and admin addresses
     *               - initial pool configurations
     */
    function initialize(VaultInitialParamsV2 memory params) external;

    // ============================================
    // APY AND RATE QUERIES
    // ============================================

    /**
     * @notice Returns the current annual percentage yield based on accreting principal
     * @dev APY is calculated based on the vault's current performance and accruing interest.
     *      This is a dynamic value that reflects real-time vault performance.
     * @return The current APY as a uint256 value (e.g., 5% APY = 0.05e8)
     */
    function apy() external view returns (uint256);

    /**
     * @notice Returns the minimum guaranteed APY for the vault
     * @dev This represents the floor APY that the vault aims to maintain.
     *      Changes to this value require timelock approval for security.
     * @return The minimum APY as a uint64 value (e.g., 5% APY = 0.05e8)
     */
    function minApy() external view returns (uint64);

    // ============================================
    // PENDING PARAMETER QUERIES
    // ============================================

    /**
     * @notice Returns the pending minimum APY update details
     * @dev Contains the proposed new value and timing information for the pending change.
     *      Used to track timelock status and proposed changes.
     * @return PendingUint192 struct with pending minimum APY data, structure includes:
     *         - newValue: the proposed new minimum APY
     *         - validAt: the timestamp when the change becomes valid
     *         - isActive: whether there's an active pending change
     */
    function pendingMinApy() external view returns (PendingUint192 memory);

    /**
     * @notice Returns the pending pool value
     * @dev Contains the proposed new value and timing information for the pending change.
     *      Used to track timelock status and proposed changes.
     * @return PendingAddress struct with pending pool data, structure includes:
     *         - newValue: the proposed new pool address
     *         - validAt: the timestamp when the change becomes valid
     */
    function pendingPool() external view returns (PendingAddress memory);

    // ============================================
    // PARAMETER SUBMISSION (TIMELOCK INITIATION)
    // ============================================

    /**
     * @notice Submits a new minimum APY for pending approval
     * @dev Initiates a timelock period before the new minimum APY can be applied.
     *      Only authorized governance can call this function.
     * @param newMinApy The proposed new minimum APY value (e.g., 5% APY = 0.05e8)
     */
    function submitPendingMinApy(uint64 newMinApy) external;

    /**
     * @notice Submits a new pool for pending approval
     * @dev Initiates a timelock period before the new pool can be used for earning yield.
     * @param pool The address of the ERC4626 pool
     */
    function submitPendingPool(address pool) external;

    // ============================================
    // PARAMETER ACCEPTANCE (TIMELOCK COMPLETION)
    // ============================================

    /**
     * @notice Accepts and applies the pending minimum APY change
     * @dev Can only be called after the timelock period has elapsed.
     *      Finalizes the APY change and updates the active minimum APY.
     */
    function acceptPendingMinApy() external;

    // ============================================
    // PARAMETER REVOCATION (TIMELOCK CANCELLATION)
    // ============================================

    /**
     * @notice Revokes the pending minimum APY change
     * @dev Cancels the pending change and resets the pending state.
     *      Allows governance to cancel proposed changes before they take effect.
     */
    function revokePendingMinApy() external;

    /**
     * @notice Revokes a pending pool change
     * @dev Cancels the pending change and resets the pending state.
     *      Allows governance to abort pool changes before they take effect.
     */
    function revokePendingPool() external;

    // ============================================
    // ORDER MANAGEMENT
    // ============================================

    /**
     * @notice Updates the curve configuration for multiple orders
     * @dev Allows batch updating of order curve parameters for gas efficiency.
     *      Curve cuts define the pricing and liquidity distribution curves.
     * @param orders The list of order addresses to update
     * @param newCurveCuts The new curve configuration parameters for each order
     */
    function updateOrderCurves(address[] memory orders, CurveCuts[] memory newCurveCuts) external;

    /**
     * @notice Updates the general configuration and liquidity for multiple orders
     * @dev Batch operation to update order configurations including:
     *      - Liquidity parameters
     *      - Fee structures
     *      - Risk parameters
     * @param orders The list of order addresses to update
     * @param params The new configuration parameters for each order
     */
    function updateOrdersConfigAndLiquidity(address[] memory orders, OrderV2ConfigurationParams[] memory params)
        external;

    /**
     * @notice Creates a new order with the specified parameters
     * @dev Deploys a new TermMax order contract with the given configuration.
     *      The order will be associated with the specified market and pool.
     * @param market The TermMax market address that the order will operate in
     * @param params The configuration parameters for the new order including:
     *               - Liquidity settings
     *               - Fee structures
     *               - Risk parameters
     * @param curveCuts The curve cuts defining pricing and liquidity curves
     * @return order The address of the newly created TermMax order contract
     */
    function createOrder(ITermMaxMarketV2 market, OrderV2ConfigurationParams memory params, CurveCuts memory curveCuts)
        external
        returns (ITermMaxOrderV2 order);
}
