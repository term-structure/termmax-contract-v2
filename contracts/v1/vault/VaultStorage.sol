// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {PendingAddress, PendingUint192} from "../lib/PendingLib.sol";

struct OrderInfo {
    ITermMaxMarket market;
    IERC20 ft;
    IERC20 xt;
    uint128 maxSupply;
    uint64 maturity;
}

contract VaultStorage {
    // State variables
    address internal _guardian;
    address internal _curator;

    mapping(address => bool) internal _isAllocator;
    mapping(address => bool) internal _marketWhitelist;
    mapping(address => PendingUint192) internal _pendingMarkets;

    PendingUint192 internal _pendingTimelock;
    PendingUint192 internal _pendingPerformanceFeeRate;
    PendingAddress internal _pendingGuardian;

    uint256 internal _timelock;
    uint256 internal _maxCapacity;

    /// @dev The total ft in the vault
    uint256 internal _totalFt;
    /// @notice The locked ft = accretingPrincipal + performanceFee;
    uint256 internal _accretingPrincipal;
    /// @notice The performance fee is paid to the curators
    uint256 internal _performanceFee;
    /// @notice Annualize the interest income
    uint256 internal _annualizedInterest;

    uint64 internal _performanceFeeRate;

    address[] internal _supplyQueue;
    address[] internal _withdrawQueue;

    /// @dev A mapping from collateral address to bad debt
    mapping(address => uint256) internal _badDebtMapping;
    mapping(address => OrderInfo) internal _orderMapping;

    /// @dev The last time the interest was accurately calculated
    uint64 internal _lastUpdateTime;
    /// @dev A one-way linked list presented using a mapping structure, recorded in order according to matiruty
    /// @dev The key is the maturity, and the value is the next maturity
    /// Etc. day 0 => day 1 => day 2 => day 3 => ...
    mapping(uint64 => uint64) internal _maturityMapping;
    /// @dev A mapping from maturity to its annualized interest
    mapping(uint64 => uint256) internal _maturityToInterest;
}
