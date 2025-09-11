// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Order Errors v2
 * @author Term Structure Labs
 */
interface OrderErrorsV2 {
    /// @notice Error thrown when an invalid or unsupported functions is called
    error UseOrderInitializationFunctionV2();

    /// @notice Error thrown when an invalid virtual XT reserve is set
    error PriceChangedBeforeSet();

    /// @notice Error thrown when attempting to update fee config on an order
    /// The v2 orders call the fee config from the market and cannot be updated individually
    error FeeConfigCanNotBeUpdated();
}
