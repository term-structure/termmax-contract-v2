// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITradeCallback {
    function tradeCallback(uint256 ftReserve) external;
}
