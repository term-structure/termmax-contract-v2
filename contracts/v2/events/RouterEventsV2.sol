// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderConfig} from "../../v1/storage/TermMaxStorage.sol";

/**
 * @title Router Events V2
 * @author Term Structure Labs
 * @notice Interface defining events for the TermMax V2 protocol's router operations
 */
interface RouterEventsV2 {
    /**
     * @notice Emitted when a new order is placed in the TermMax V2 protocol
     * @dev This event is triggered when a user places an order, providing details about the maker,
     * the order itself, the market involved, and the configuration of the order.
     * @param maker The address of the user who placed the order
     * @param order The address of the new order contract
     * @param market The address of the market where this order is placed
     * @param gtId The id of the gearing token
     * @param config The configuration details of the order, encapsulated in an OrderConfig struct
     */
    event PlaceOrderForV1(
        address indexed maker, address indexed order, address market, uint256 gtId, OrderConfig config
    );
}
