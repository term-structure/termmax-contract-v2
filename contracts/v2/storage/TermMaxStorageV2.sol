// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct VaultInitialParamsV2 {
    address admin;
    address curator;
    address guardian;
    uint256 timelock;
    IERC20 asset;
    uint256 maxCapacity;
    string name;
    string symbol;
    /// @notice The performance fee rate in base units, e.g. 20% = 0.2e8
    uint64 performanceFeeRate;
    /// @notice The minimum APY in base units, e.g. 2% = 0.02e8
    uint64 minApy;
    /// @notice The minimum idle fund rate in base units, e.g. 10% = 0.1e8
    uint64 minIdleFundRate;
}
