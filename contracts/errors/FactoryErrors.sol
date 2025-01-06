// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface FactoryErrors {
    /// @notice Error for repeat initialization of market's implementation
    error InvalidMarketImplement();

    /// @notice Error for gt implementation can not found
    error CantNotFindGtImplementation();
}
