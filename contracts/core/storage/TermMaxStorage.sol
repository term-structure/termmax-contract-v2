// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library TermMaxStorage {
    struct MarketConfig {
        uint256 minLeveragedXt;
        uint256 minLeveredFt;
        uint64 maturity;
        uint64 openTime;
        int64 apy;
        uint32 gamma;
        uint32 lendFeeRatio;
        uint32 borrowFeeRatio;
        // The loan to collateral while generating ft/xt tokens
        uint32 initialLtv;
        // Whether liquidating g-nft when it's ltv bigger than liquidationLtv
        bool liquidatable;
        bool deliverable;
        bool rewardIsDistributed;
    }
}
