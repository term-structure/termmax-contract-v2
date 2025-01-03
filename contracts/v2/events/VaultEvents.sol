// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface VaultEvents {
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
