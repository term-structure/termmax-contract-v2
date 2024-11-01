// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library TermMaxStorage {
    struct MarketConfig {
        address treasurer;
        uint64 maturity;
        uint64 openTime;
        int64 apr;
        // The liquidity scaling factor
        uint32 lsf;
        uint32 lendFeeRatio;
        // The minmally notional lending fee ratio
        uint32 minNLendFeeR;
        uint32 borrowFeeRatio;
        // The minmally notional borrowing fee ratio
        uint32 minNBorrowFeeR;
        uint32 redeemFeeRatio;
        uint32 leverfeeRatio;
        // The locking percentage of transaction fees
        uint32 lockingFeeRatio;
        // The loan to collateral while generating ft/xt tokens
        uint32 initialLtv;
        // THe percentage of transaction fees to protocol
        uint32 protocolFeeRatio;
        // Whether the lp rewards is distributed after maturity
        bool rewardIsDistributed;
    }
}
