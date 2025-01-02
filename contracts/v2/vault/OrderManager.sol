// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PendingLib, PendingAddress, PendingUint192, PendingCurveCuts} from "../lib/PendingLib.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {VaultErrors} from "../errors/VaultErrors.sol";

abstract contract OrderManager is VaultErrors {
    using PendingLib for *;

    PendingAddress public pendingGuardian;
    address public curator;

    address[] public supplyQueue;
    address[] public withdrawQueue;

    mapping(uint16 => PendingCurveCuts) public pendingCurveCuts;

    mapping(address => PendingUint192) public pendingCap;

    PendingUint192 public pendingTimelock;

    modifier onlyCurator() {
        require(msg.sender == curator);
        _;
    }

    /// @dev Makes sure conditions are met to accept a pending value.
    /// @dev Reverts if:
    /// - there's no pending value;
    /// - the timelock has not elapsed since the pending value has been submitted.
    modifier afterTimelock(uint256 validAt) {
        if (validAt == 0) revert NoPendingValue();
        if (block.timestamp < validAt) revert TimelockNotElapsed();
        _;
    }

    function createOrder(
        ITermMaxMarket market,
        uint256 maxXtReserve,
        uint16 curveId,
        uint192 capacity
    ) external afterTimelock(pendingCurveCuts[curveId].validAt) onlyCurator {
        market.createOrder(address(this), maxXtReserve, pendingCurveCuts[curveId].curveCuts);
    }

    function supplyQueueLength() external view returns (uint256) {
        return supplyQueue.length;
    }

    function withdrawQueueLength() external view returns (uint256) {
        return withdrawQueue.length;
    }
}
