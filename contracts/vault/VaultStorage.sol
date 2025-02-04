// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PendingAddress, PendingUint192} from "contracts/lib/PendingLib.sol";

struct OrderInfo {
    ITermMaxMarket market;
    IERC20 ft;
    IERC20 xt;
    uint128 maxSupply;
    uint64 maturity;
}

contract VaultStorage {
    address guardian;
    address curator;

    mapping(address => bool) isAllocator;

    mapping(address => bool) marketWhitelist;

    mapping(address => PendingUint192) pendingMarkets;

    PendingUint192 pendingTimelock;
    PendingUint192 pendingPerformanceFeeRate;
    PendingAddress pendingGuardian;

    uint256 timelock;
    uint256 maxCapacity;

    /// @dev The total ft in the vault
    uint256 totalFt;
    /// @notice The locked ft = accretingPrincipal + performanceFee;
    uint256 accretingPrincipal;
    /// @notice The performance fee is paid to the curators
    uint256 performanceFee;
    /// @notice Annualize the interest income
    uint256 annualizedInterest;

    uint64 performanceFeeRate;

    address[] supplyQueue;

    address[] withdrawQueue;

    /// @dev A mapping from collateral address to bad debt
    mapping(address => uint256) badDebtMapping;
    mapping(address => OrderInfo) orderMapping;

    /// @dev The last time the interest was accurately calculated
    uint64 lastUpdateTime;
    /// @dev The recentest maturity
    uint64 recentestMaturity;
    /// @dev A one-way linked list presented using a mapping structure, recorded in order according to matiruty
    /// @dev The key is the maturity, and the value is the next maturity
    /// Etc. day 0 => day 1 => day 2 => day 3 => ...
    mapping(uint64 => uint64) maturityMapping;
    /// @dev A mapping from maturity to its annualized interest
    mapping(uint64 => uint128) maturityToInterest;
}
