// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title IOracleV2
 * @author Term Structure Labs
 * @notice Enhanced oracle interface for TermMax V2 protocol with improved price feed management
 * @dev Extends the V1 oracle interface with additional features including price caps, separate backup heartbeats,
 * and oracle revocation capabilities for enhanced security and flexibility
 */
interface IOracleV2 {
    /**
     * @notice Oracle configuration structure for price feed management
     * @dev Contains primary and backup aggregators with independent heartbeat configurations
     * @param aggregator Primary price feed aggregator (required)
     * @param backupAggregator Secondary price feed aggregator for fallback (optional)
     * @param maxPrice Maximum allowed price value for this asset (0 = no limit)
     * @param heartbeat Maximum allowed staleness for primary aggregator in seconds (0 = no staleness check)
     * @param backupHeartbeat Maximum allowed staleness for backup aggregator in seconds (0 = no staleness check)
     */
    struct Oracle {
        AggregatorV3Interface aggregator;
        AggregatorV3Interface backupAggregator;
        int256 maxPrice;
        int256 minPrice;
        uint32 heartbeat;
        uint32 backupHeartbeat;
    }

    /**
     * @notice Error thrown when the oracle system cannot provide a reliable price
     * @dev Occurs when both primary and backup oracles are stale, returning invalid data, or when no oracle is configured
     * @param asset The address of the asset for which the oracle is not working
     */
    error OracleIsNotWorking(address asset);

    /**
     * @notice Retrieves the current price of an asset from the oracle system
     * @dev Uses primary oracle first, falls back to backup if primary is stale or invalid
     * Applies maxPrice cap if configured. Returns price with the aggregator's native decimals
     * @param asset The address of the asset to get the price for
     * @return price The current price of the asset (may be capped by maxPrice)
     * @return decimals The number of decimal places in the returned price
     * @custom:reverts OracleIsNotWorking if no valid price can be obtained
     */
    function getPrice(address asset) external view returns (uint256 price, uint8 decimals);

    /**
     * @notice Submits a new oracle configuration for an asset with timelock protection
     * @dev Creates a pending oracle update that must wait for the timelock period before activation
     * Used for adding new oracles or updating existing ones with enhanced security
     * @param asset The address of the asset to configure the oracle for
     * @param oracle The oracle configuration structure with primary/backup feeds and settings
     * @custom:access Typically restricted to oracle managers or governance
     * @custom:security Subject to timelock delay for security
     */
    function submitPendingOracle(address asset, Oracle memory oracle) external;

    /**
     * @notice Activates a previously submitted pending oracle configuration
     * @dev Can only be called after the timelock period has elapsed since submission
     * Replaces the current oracle configuration with the pending one
     * @param asset The address of the asset to accept the pending oracle for
     * @custom:access Usually callable by anyone after timelock expires
     * @custom:validation Requires valid pending oracle and elapsed timelock
     */
    function acceptPendingOracle(address asset) external;

    /**
     * @notice Cancels a pending oracle configuration before it can be accepted
     * @dev Allows oracle managers to revoke pending updates if errors are discovered
     * Can only revoke pending oracles that haven't been accepted yet
     * @param asset The address of the asset to revoke the pending oracle for
     * @custom:access Typically restricted to oracle managers or governance
     * @custom:security Provides emergency mechanism to cancel erroneous oracle updates
     */
    function revokePendingOracle(address asset) external;
}
