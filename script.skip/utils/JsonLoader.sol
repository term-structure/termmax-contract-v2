// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

library JsonLoader {
    using stdJson for string;

    struct MarketConfig {
        uint64 openTime;
        uint64 maturity;
        uint32 initialLtv;
        int64 apr;
        uint32 lsf;
        uint32 lendFeeRatio;
        uint32 borrowFeeRatio;
        uint32 issueFtFeeRatio;
        uint32 lockingPercentage;
        uint32 protocolFeeRatio;
        uint32 minNLendFeeR;
        uint32 minNBorrowFeeR;
        uint32 redeemFeeRatio;
        uint32 maxLtv;
        uint32 liquidationLtv;
        bool liquidatable;
        address treasurer;
    }

    struct UnderlyingConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 mintAmt;
        int256 initialPrice;
    }

    struct CollateralConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 mintAmt;
        int256 initialPrice;
        string gtKeyIdentifier;
    }

    struct Config {
        MarketConfig marketConfig;
        UnderlyingConfig underlyingConfig;
        CollateralConfig collateralConfig;
    }

    Vm constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getConfigsFromJson(
        string memory jsonData
    ) internal pure returns (Config[] memory configs) {
        uint256 configNum = uint256(
            vm.parseUint(vm.parseJsonString(jsonData, ".configNum"))
        );
        configs = new Config[](configNum);
        for (uint256 i; i < configNum; i++) {
            Config memory config = getConfigFromJson(jsonData, i);
            configs[i] = config;
        }
    }

    function getConfigFromJson(
        string memory jsonData,
        uint256 index
    ) internal pure returns (Config memory config) {
        MarketConfig memory marketConfig;
        UnderlyingConfig memory underlyingConfig;
        CollateralConfig memory collateralConfig;
        string memory configPrefix = string.concat(
            ".configs",
            ".configs_",
            vm.toString(index)
        );
        string memory marketConfigPrefix = string.concat(
            configPrefix,
            ".marketConfig"
        );
        marketConfig.openTime = uint64(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".openTime")
                )
            )
        );
        marketConfig.maturity = uint64(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".maturity")
                )
            )
        );
        marketConfig.initialLtv = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".initialLtv")
                )
            )
        );
        marketConfig.apr = int64(
            vm.parseInt(
                jsonData.readString(string.concat(marketConfigPrefix, ".apr"))
            )
        );
        marketConfig.lsf = uint32(
            vm.parseUint(
                jsonData.readString(string.concat(marketConfigPrefix, ".lsf"))
            )
        );
        marketConfig.lendFeeRatio = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".lendFeeRatio")
                )
            )
        );
        marketConfig.borrowFeeRatio = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".borrowFeeRatio")
                )
            )
        );
        marketConfig.issueFtFeeRatio = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".issueFtFeeRatio")
                )
            )
        );
        marketConfig.lockingPercentage = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".lockingPercentage")
                )
            )
        );
        marketConfig.protocolFeeRatio = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".protocolFeeRatio")
                )
            )
        );
        marketConfig.minNLendFeeR = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".minNLendFeeR")
                )
            )
        );
        marketConfig.minNBorrowFeeR = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".minNBorrowFeeR")
                )
            )
        );
        marketConfig.redeemFeeRatio = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".redeemFeeRatio")
                )
            )
        );
        marketConfig.maxLtv = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".maxLtv")
                )
            )
        );
        marketConfig.liquidationLtv = uint32(
            vm.parseUint(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".liquidationLtv")
                )
            )
        );
        marketConfig.liquidatable = bool(
            vm.parseBool(
                jsonData.readString(
                    string.concat(marketConfigPrefix, ".liquidatable")
                )
            )
        );
        marketConfig.treasurer = vm.parseAddress(
            jsonData.readString(string.concat(marketConfigPrefix, ".treasurer"))
        );

        string memory underlyingConfigPrefix = string.concat(
            configPrefix,
            ".underlyingConfig"
        );
        underlyingConfig.name = jsonData.readString(
            string.concat(underlyingConfigPrefix, ".name")
        );
        underlyingConfig.symbol = jsonData.readString(
            string.concat(underlyingConfigPrefix, ".symbol")
        );
        underlyingConfig.decimals = uint8(
            vm.parseUint(
                jsonData.readString(
                    string.concat(underlyingConfigPrefix, ".decimals")
                )
            )
        );
        underlyingConfig.mintAmt = vm.parseUint(
            jsonData.readString(
                string.concat(underlyingConfigPrefix, ".mintAmt")
            )
        );
        underlyingConfig.initialPrice = vm.parseInt(
            jsonData.readString(
                string.concat(underlyingConfigPrefix, ".initialPrice")
            )
        );

        string memory collateralConfigPrefix = string.concat(
            configPrefix,
            ".collateralConfig"
        );
        collateralConfig.name = jsonData.readString(
            string.concat(collateralConfigPrefix, ".name")
        );
        collateralConfig.symbol = jsonData.readString(
            string.concat(collateralConfigPrefix, ".symbol")
        );
        collateralConfig.decimals = uint8(
            vm.parseUint(
                jsonData.readString(
                    string.concat(collateralConfigPrefix, ".decimals")
                )
            )
        );
        collateralConfig.decimals = uint8(
            vm.parseUint(
                jsonData.readString(
                    string.concat(collateralConfigPrefix, ".decimals")
                )
            )
        );
        collateralConfig.mintAmt = vm.parseUint(
            jsonData.readString(
                string.concat(collateralConfigPrefix, ".mintAmt")
            )
        );
        collateralConfig.initialPrice = vm.parseInt(
            jsonData.readString(
                string.concat(collateralConfigPrefix, ".initialPrice")
            )
        );
        collateralConfig.gtKeyIdentifier = jsonData.readString(
            string.concat(collateralConfigPrefix, ".gtKeyIdentifier")
        );

        config = Config({
            marketConfig: marketConfig,
            underlyingConfig: underlyingConfig,
            collateralConfig: collateralConfig
        });
    }
}
