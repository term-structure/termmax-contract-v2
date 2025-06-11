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
    uint64 performanceFeeRate;
    uint64 minApy;
    uint64 minIdleFundRate;
}
