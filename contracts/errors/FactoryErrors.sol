// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Factory Errors Interface
 * @notice Custom errors for the TermMax factory operations
 */
interface FactoryErrors {
    /**
     * @notice Error thrown when attempting to initialize a market with an invalid implementation
     * @dev This can occur when trying to set an implementation that's already been set or is invalid
     */
    error InvalidMarketImplementation();

    /**
     * @notice Error thrown when a requested Gearing Token implementation cannot be found
     * @dev This occurs when trying to use a GT implementation that hasn't been registered
     */
    error CantNotFindGtImplementation();
}
