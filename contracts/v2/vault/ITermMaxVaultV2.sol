// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PendingAddress, PendingUint192} from "../../v1/lib/PendingLib.sol";
import {VaultInitialParamsV2} from "../storage/TermMaxStorageV2.sol";

/**
 * @title ITermMaxVaultV2
 * @notice Interface for TermMax Vault V2 contract
 * @dev This interface defines the core functionality for vault operations including
 *      initialization, APY management, and pending parameter updates with timelock mechanism
 */
interface ITermMaxVaultV2 {
    /**
     * @notice Initializes the vault with the provided parameters
     * @dev This function should only be called once during contract deployment
     * @param params The initial configuration parameters for the vault
     */
    function initialize(VaultInitialParamsV2 memory params) external;

    /**
     * @notice Returns the current annual percentage yield based on accreting principal
     * @dev APY is calculated based on the vault's current performance and accruing interest
     * @return The current APY as a uint256 value
     */
    function apy() external view returns (uint256);

    /**
     * @notice Returns the minimum guaranteed APY for the vault
     * @dev This represents the floor APY that the vault aims to maintain
     * @return The minimum APY as a uint64 value
     */
    function minApy() external view returns (uint64);

    /**
     * @notice Returns the minimum rate for idle funds in the vault
     * @dev This rate applies to funds that are not actively deployed in strategies
     * @return The minimum idle fund rate as a uint64 value
     */
    function minIdleFundRate() external view returns (uint64);

    /**
     * @notice Returns the pending minimum APY update details
     * @dev Contains the proposed new value and timing information for the pending change
     * @return PendingUint192 struct with pending minimum APY data
     */
    function pendingMinApy() external view returns (PendingUint192 memory);

    /**
     * @notice Returns the pending minimum idle fund rate update details
     * @dev Contains the proposed new value and timing information for the pending change
     * @return PendingUint192 struct with pending minimum idle fund rate data
     */
    function pendingMinIdleFundRate() external view returns (PendingUint192 memory);

    /**
     * @notice Submits a new minimum APY for pending approval
     * @dev Initiates a timelock period before the new minimum APY can be applied
     * @param newMinApy The proposed new minimum APY value
     */
    function submitPendingMinApy(uint64 newMinApy) external;

    /**
     * @notice Submits a new minimum idle fund rate for pending approval
     * @dev Initiates a timelock period before the new rate can be applied
     * @param newMinIdleFundRate The proposed new minimum idle fund rate
     */
    function submitPendingMinIdleFundRate(uint64 newMinIdleFundRate) external;

    /**
     * @notice Accepts and applies the pending minimum APY change
     * @dev Can only be called after the timelock period has elapsed
     */
    function acceptPendingMinApy() external;

    /**
     * @notice Accepts and applies the pending minimum idle fund rate change
     * @dev Can only be called after the timelock period has elapsed
     */
    function acceptPendingMinIdleFundRate() external;

    /**
     * @notice Revokes the pending minimum APY change
     * @dev Cancels the pending change and resets the pending state
     */
    function revokePendingMinApy() external;

    /**
     * @notice Revokes the pending minimum idle fund rate change
     * @dev Cancels the pending change and resets the pending state
     */
    function revokePendingMinIdleFundRate() external;
}
