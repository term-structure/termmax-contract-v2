// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TermMax Swap Callback Interface
 * @author Term Structure Labs
 * @notice Interface for handling callbacks after swap operations in TermMax
 */
interface ISwapCallback {
    /**
     * @notice Callback function called after a swap operation
     * @param ftReserve The reserve of the FT token
     * @param xtReserve The reserve of the XT token
     * @param deltaFt The change in FT token balance (positive for receiving, negative for paying)
     * @param deltaXt The change in XT token balance (positive for receiving, negative for paying)
     */
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256 deltaXt) external;
}
