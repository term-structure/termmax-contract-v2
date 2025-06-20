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
    event PlaceOrder(address indexed maker, address indexed order, address market, uint256 gtId, OrderConfig config);

    // /**
    //  * @notice Emitted when a repay operation is performed through ft
    //  * @param market The address of the market
    //  * @param gtId The id of the gt
    //  * @param caller The address initiating the repay
    //  * @param recipient The address receiving the repaid tokens
    //  * @param repayAmt The amount of tokens repaid
    //  * @param netCost The amount of tokens spent to by ft tokens
    //  */
    // event RepayByTokenThroughFt(
    //     address indexed market,
    //     uint256 indexed gtId,
    //     address caller,
    //     address recipient,
    //     uint256 repayAmt,
    //     uint256 netCost
    // );
}
