// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract OnlyProxyCall {
    error OnlyCallableThroughProxy();

    address private immutable addressThis;

    constructor() {
        // Store the address of the contract at deployment
        addressThis = address(this);
    }

    /// @notice Modifier to restrict function calls to only be made through the proxy
    /// @dev This ensures that the function can only be called via the proxy contract, preventing direct calls
    modifier onlyProxy() {
        require(addressThis != address(this), OnlyCallableThroughProxy());
        _;
    }
}
