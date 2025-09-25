// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OrderConfig} from "../../v1/storage/TermMaxStorage.sol";
import {OrderInitialParams} from "../storage/TermMaxStorageV2.sol";

/**
 * @title Router Events V2
 * @author Term Structure Labs
 * @notice Interface defining events for the TermMax V2 protocol's router operations
 */
interface RouterEventsV2 {
    event WhitelistManagerUpdated(address whitelistManager);

    event SwapAndRepay(address indexed gt, uint256 indexed gtId, uint256 repayAmt, uint256 remainingRepayToken);

    event FlashRepay(address indexed gt, uint256 indexed gtId, uint256 netTokenOut);

    event RolloverGt(
        address indexed gt,
        uint256 indexed gtId,
        uint256 indexed newGtId,
        address additionalAsset,
        uint256 additionalAmt
    );
}
