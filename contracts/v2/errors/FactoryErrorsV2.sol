// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Factory Errors Interface V2
 * @notice Custom errors for the TermMax factory operations V2
 */
interface FactoryErrorsV2 {
    error ImplementationNotFound(string key);
    error InitializationFailed();
}
