// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ISyntheticSharesOracle {
    /**
     * @notice Returns the Asset struct for a given asset
     * @param asset The address of the asset
     * @return sValue The current sValue of the asset
     * @return pendingSValue The pending sValue of the asset, if a corporate action is scheduled
     * @return lastUpdate The last time the asset was updated
     * @return pauseStartTime The start time of the pause window, if a corporate action is scheduled
     * @return allowedDriftBps The drift denoted in basis points (e.g., 100 for 1%)
     * @return driftCooldown The time required to wait before updating the sValue again, denoted in
     *                         seconds (e.g., 86400 for 24 hours)
     */
    function assetData(address asset)
        external
        view
        returns (
            uint128 sValue,
            uint128 pendingSValue,
            uint256 lastUpdate,
            uint256 pauseStartTime,
            uint16 allowedDriftBps,
            uint48 driftCooldown
        );
}
