// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Factory Errors Interface
 * @notice Custom errors for the TermMax factory operations
 */
interface FactoryErrors {
    /**
     * @notice Error thrown when attempting to initialize with an invalid implementation
     */
    error InvalidImplementation();

    /**
     * @notice Error thrown when a requested Gearing Token implementation cannot be found
     * @dev This occurs when trying to use a GT implementation that hasn't been registered
     */
    error CantNotFindGtImplementation();
}
