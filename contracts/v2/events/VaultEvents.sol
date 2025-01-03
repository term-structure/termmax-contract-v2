// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface VaultEvents {
    event SubmitTimelock(uint256 newTimelock);
    event SetTimelock(address caller, uint256 newTimelock);
    event SetGuardian(address caller, address newGuardian);
    event RevokePendingTimelock(address caller);
    event RevokePendingGuardian(address caller);
}
