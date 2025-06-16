// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderConfig} from "../../v1/storage/TermMaxStorage.sol";

/**
 * @title Order Events v2
 * @author Term Structure Labs
 */
interface OrderEventsV2 {
    /// @notice Emitted when an order is initialized
    /// @param maker The address of the maker who created the order
    /// @param market The address of the market associated with the order
    /// @param orderConfig The configuration of the order
    event OrderInitialized(address indexed maker, address indexed market, OrderConfig orderConfig);
}
