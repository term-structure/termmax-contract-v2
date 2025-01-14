// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CurveCuts} from "../storage/TermMaxStorage.sol";

interface VaultEvents {
    event CreateOrder(
        address indexed caller,
        address indexed market,
        address indexed order,
        uint256 maxXtReserve,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts curveCuts
    );
    event UpdateOrder(
        address indexed caller,
        address indexed order,
        int256 changes,
        uint256 maxSupply,
        uint256 maxXtReserve,
        CurveCuts curveCuts
    );
    event DealBadDebt(address indexed recipient, address indexed collaretal, uint256 amount, uint256 collateralOut);
    event RedeemOrder(address indexed caller, address indexed order, uint128 ftAmt, uint128 redeemedAmt);

    event SubmitTimelock(uint256 newTimelock);
    event SetTimelock(address indexed caller, uint256 newTimelock);
    event SetGuardian(address indexed caller, address newGuardian);
    event RevokePendingTimelock(address indexed caller);
    event RevokePendingGuardian(address indexed caller);
    event SetCap(address indexed caller, address indexed order, uint256 newCap);
    event SetIsAllocator(address indexed allocator, bool newIsAllocator);
    event UpdateSupplyQueue(address indexed caller, address[] newSupplyQueue);
    event UpdateWithdrawQueue(address indexed caller, address[] newWithdrawQueue);
}
