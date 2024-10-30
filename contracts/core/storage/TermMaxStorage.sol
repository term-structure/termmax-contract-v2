// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library TermMaxStorage {
    struct MarketConfig {
        uint256 minLeveragedXt;
        uint256 minLeveredFt;
        address treasurer;
        uint64 maturity;
        uint64 openTime;
        int64 apr;
        // The liquidity scaling factor
        uint32 lsf;
        uint32 lendFeeRatio;
        uint32 borrowFeeRatio;
        // The locking percentage of transaction fees
        uint32 lockingFeeRatio;
        // The loan to collateral while generating ft/xt tokens
        uint32 initialLtv;
        // THe percentage of transaction fees to protocol
        uint32 protocolFeeRatio;
        // Whether liquidating g-nft when it's ltv bigger than liquidationLtv
        bool liquidatable;
        // Whether deliverying collateral after maturity
        bool deliverable;
        // Whether the lp rewards is distributed after maturity
        bool rewardIsDistributed;
    }
}
