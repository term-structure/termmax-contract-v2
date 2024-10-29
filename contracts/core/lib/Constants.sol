// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library Constants {
    string constant PREFIX_FT = "FT:";
    string constant PREFIX_XT = "XT:";
    string constant PREFIX_LP_FT = "LpFT:";
    string constant PREFIX_LP_XT = "LpXT:";
    string constant PREFIX_GNFT = "GNFT:";
    string constant STRING_UNDER_LINE = "_";
    uint32 constant DECIMAL_BASE = 1e8;
    uint64 constant DECIMAL_BASE_SQRT = 1e16;
    uint16 constant DAYS_IN_YEAR = 365;
    uint32 constant SECONDS_IN_DAY = 86400;
    uint32 constant SECONDS_IN_MOUNTH = 2592000;
    // The percentage of repay amount to liquidator while do liquidate
    uint32 constant REWARD_TO_LIQUIDATOR = 5e6;
    // The percentage of repay amount to protocol while do liquidate
    uint32 constant REWARD_TO_PROTOCOL = 5e6;
}
