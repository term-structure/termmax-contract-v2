// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {OrderConfig} from "../../v1/storage/TermMaxStorage.sol";

struct VaultInitialParamsV2 {
    address admin;
    address curator;
    address guardian;
    uint256 timelock;
    IERC20 asset;
    /// @notice The third-party pool to earn floating interest by idle funds
    IERC4626 pool;
    uint256 maxCapacity;
    string name;
    string symbol;
    /// @notice The performance fee rate in base units, e.g. 20% = 0.2e8
    uint64 performanceFeeRate;
    /// @notice The minimum APY in base units, e.g. 2% = 0.02e8
    uint64 minApy;
}

struct OrderInitialParams {
    address maker;
    IERC20 ft;
    IERC20 xt;
    IERC20 debtToken;
    IGearingToken gt;
    uint256 virtualXtReserve;
    IERC4626 pool;
    uint64 maturity;
    OrderConfig orderConfig;
}
