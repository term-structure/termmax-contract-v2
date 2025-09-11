// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {PendingAddress, PendingUint192} from "../../v1/lib/PendingLib.sol";
import {CurveCuts} from "../../v1/storage/TermMaxStorage.sol";

struct OrderV2ConfigurationParams {
    uint256 originalVirtualXtReserve;
    uint256 virtualXtReserve;
    uint256 maxXtReserve;
    CurveCuts curveCuts;
}

contract VaultStorageV2 {
    // State variables
    address internal _guardian;
    address internal _curator;

    mapping(address => bool) internal _marketWhitelist;
    mapping(address => bool) internal _poolWhitelist;
    mapping(address => PendingUint192) internal _pendingMarkets;

    PendingUint192 internal _pendingTimelock;
    PendingUint192 internal _pendingPerformanceFeeRate;
    PendingAddress internal _pendingGuardian;
    PendingUint192 internal _pendingMinApy;
    PendingAddress internal _pendingPool;

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
    /// @notice The third-party pool to earn floating interest by idle funds
    IERC4626 internal _pool;

    /// @notice A mapping from collateral address to bad debt
    mapping(address => uint256) internal _badDebtMapping;

    /// @notice A mapping from order address to its maturity
    mapping(address => uint256) internal _orderMaturityMapping;

    /// @notice A one-way linked list presented using a mapping structure, recorded in order according to matiruty
    /// @notice The key is the maturity, and the value is the next maturity
    /// Etc. day 0 => day 1 => day 2 => day 3 => ...
    mapping(uint64 => uint64) internal _maturityMapping;
    /// @notice A mapping from maturity to its annualized interest
    mapping(uint64 => uint256) internal _maturityToInterest;

    /// @notice The performance fee rate, in basis points (1e8 = 100%)
    uint64 internal _performanceFeeRate;

    /// @notice The last time the interest was accurately calculated
    uint64 internal _lastUpdateTime;

    /// @notice The minimum APY for the vault to be active
    uint64 internal _minApy;
}
