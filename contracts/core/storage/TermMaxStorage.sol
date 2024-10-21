// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IMintableERC20, IERC20} from "../../interfaces/IMintableERC20.sol";
import {IGearingNft} from "../../interfaces/IGearingNft.sol";

library TermMaxStorage {
    struct MarketConfig {
        AggregatorV3Interface collateralOracle;
        //10**ya.decimals()
        uint256 minLeveragedYa;
        uint256 minLeveredYp;
        uint64 maturity;
        uint64 openTime;
        int64 apy;
        uint32 gamma;
        uint32 lendFeeRatio;
        uint32 borrowFeeRatio;
        // The loan to collateral while generating ft/xt tokens
        uint32 initialLtv;
        // The loan to collateral of g-nft liquidation threshhold
        uint32 liquidationLtv;
        // The loan to collateral while minting g-nft
        uint32 maxLtv;
        // Whether liquidating g-nft when it's ltv bigger than liquidationLtv
        bool liquidatable;
        bool deliverable;
        bool rewardIsDistributed;
    }

    struct MarketTokens {
        IMintableERC20 ya;
        IMintableERC20 yp;
        IMintableERC20 lpYa;
        IMintableERC20 lpYp;
        IGearingNft gNft;
        address collateralToken;
        IERC20 cash;
    }

    bytes32 internal constant STORAGE_SLOT_MARKET_CONFIG =
        bytes32(uint256(keccak256("TermMax.storage.MarketConfig")) - 1);

    bytes32 internal constant STORAGE_SLOT_MARKET_TOKENS =
        bytes32(uint256(keccak256("TermMax.storage.MarketTokens")) - 1);

    function _getConfig() internal pure returns (MarketConfig storage s) {
        bytes32 slot = STORAGE_SLOT_MARKET_CONFIG;
        assembly {
            s.slot := slot
        }
    }

    function _getTokens() internal pure returns (MarketTokens storage s) {
        bytes32 slot = STORAGE_SLOT_MARKET_TOKENS;
        assembly {
            s.slot := slot
        }
    }
}
