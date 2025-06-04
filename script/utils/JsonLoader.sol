// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MarketConfig, FeeConfig, LoanConfig} from "contracts/v1/storage/TermMaxStorage.sol";

library JsonLoader {
    using stdJson for string;

    struct UnderlyingConfig {
        address tokenAddr;
        address priceFeedAddr;
        address backupPriceFeedAddr;
        uint256 heartBeat;
        string name;
        string symbol;
        uint8 decimals;
        int256 initialPrice;
    }

    struct CollateralConfig {
        address tokenAddr;
        address priceFeedAddr;
        address backupPriceFeedAddr;
        uint256 heartBeat;
        string name;
        string symbol;
        uint8 decimals;
        int256 initialPrice;
        string gtKeyIdentifier;
    }

    struct Config {
        string marketName;
        string marketSymbol;
        uint256 salt;
        MarketConfig marketConfig;
        LoanConfig loanConfig;
        UnderlyingConfig underlyingConfig;
        CollateralConfig collateralConfig;
        uint256 collateralCapForGt;
    }

    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getConfigsFromJson(string memory jsonData) internal pure returns (Config[] memory configs) {
        uint256 configNum = uint256(vm.parseUint(vm.parseJsonString(jsonData, ".configNum")));
        configs = new Config[](configNum);
        for (uint256 i; i < configNum; i++) {
            Config memory config = getConfigFromJson(jsonData, i);
            configs[i] = config;
        }
    }

    function getConfigFromJson(string memory jsonData, uint256 index) internal pure returns (Config memory config) {
        MarketConfig memory marketConfig;
        LoanConfig memory loanConfig;
        UnderlyingConfig memory underlyingConfig;
        CollateralConfig memory collateralConfig;
        uint256 salt;
        uint256 collateralCapForGt;
        string memory configPrefix = string.concat(".configs", ".configs_", vm.toString(index));

        // read salt
        salt = uint256(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".salt"))));

        // read collateral cap for gt
        collateralCapForGt =
            uint256(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".collateralCapForGt"))));

        // read market name and symbol
        config.marketName = jsonData.readString(string.concat(configPrefix, ".marketName"));
        config.marketSymbol = jsonData.readString(string.concat(configPrefix, ".marketSymbol"));

        // read market config
        string memory marketConfigPrefix = string.concat(configPrefix, ".marketConfig");
        marketConfig.maturity =
            uint64(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".maturity"))));
        marketConfig.feeConfig.lendTakerFeeRatio =
            uint32(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".lendTakerFeeRatio"))));
        marketConfig.feeConfig.lendMakerFeeRatio =
            uint32(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".lendMakerFeeRatio"))));
        marketConfig.feeConfig.borrowTakerFeeRatio =
            uint32(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".borrowTakerFeeRatio"))));
        marketConfig.feeConfig.borrowMakerFeeRatio =
            uint32(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".borrowMakerFeeRatio"))));
        marketConfig.feeConfig.mintGtFeeRatio =
            uint32(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".mintGtFeeRatio"))));
        marketConfig.feeConfig.mintGtFeeRef =
            uint32(vm.parseUint(jsonData.readString(string.concat(marketConfigPrefix, ".mintGtFeeRef"))));

        // read loan config
        string memory loanConfigPrefix = string.concat(configPrefix, ".loanConfig");
        loanConfig.liquidationLtv =
            uint32(vm.parseUint(jsonData.readString(string.concat(loanConfigPrefix, ".liquidationLtv"))));
        loanConfig.maxLtv = uint32(vm.parseUint(jsonData.readString(string.concat(loanConfigPrefix, ".maxLtv"))));
        loanConfig.liquidatable = vm.parseBool(jsonData.readString(string.concat(loanConfigPrefix, ".liquidatable")));

        // read underlying config
        string memory underlyingConfigPrefix = string.concat(configPrefix, ".underlyingConfig");
        underlyingConfig.tokenAddr = jsonData.readAddress(string.concat(underlyingConfigPrefix, ".tokenAddr"));
        underlyingConfig.priceFeedAddr = jsonData.readAddress(string.concat(underlyingConfigPrefix, ".priceFeedAddr"));
        underlyingConfig.backupPriceFeedAddr =
            jsonData.readAddress(string.concat(underlyingConfigPrefix, ".backupPriceFeedAddr"));
        underlyingConfig.name = jsonData.readString(string.concat(underlyingConfigPrefix, ".name"));
        underlyingConfig.symbol = jsonData.readString(string.concat(underlyingConfigPrefix, ".symbol"));
        underlyingConfig.decimals =
            uint8(vm.parseUint(jsonData.readString(string.concat(underlyingConfigPrefix, ".decimals"))));
        underlyingConfig.initialPrice =
            vm.parseInt(jsonData.readString(string.concat(underlyingConfigPrefix, ".initialPrice")));
        underlyingConfig.heartBeat =
            uint256(vm.parseUint(jsonData.readString(string.concat(underlyingConfigPrefix, ".heartBeat"))));

        // read collateral config
        string memory collateralConfigPrefix = string.concat(configPrefix, ".collateralConfig");
        collateralConfig.tokenAddr = jsonData.readAddress(string.concat(collateralConfigPrefix, ".tokenAddr"));
        collateralConfig.priceFeedAddr = jsonData.readAddress(string.concat(collateralConfigPrefix, ".priceFeedAddr"));
        collateralConfig.backupPriceFeedAddr =
            jsonData.readAddress(string.concat(collateralConfigPrefix, ".backupPriceFeedAddr"));
        collateralConfig.name = jsonData.readString(string.concat(collateralConfigPrefix, ".name"));
        collateralConfig.symbol = jsonData.readString(string.concat(collateralConfigPrefix, ".symbol"));
        collateralConfig.decimals =
            uint8(vm.parseUint(jsonData.readString(string.concat(collateralConfigPrefix, ".decimals"))));
        collateralConfig.initialPrice =
            vm.parseInt(jsonData.readString(string.concat(collateralConfigPrefix, ".initialPrice")));
        collateralConfig.gtKeyIdentifier =
            jsonData.readString(string.concat(collateralConfigPrefix, ".gtKeyIdentifier"));
        collateralConfig.heartBeat =
            uint256(vm.parseUint(jsonData.readString(string.concat(collateralConfigPrefix, ".heartBeat"))));

        config.salt = salt;
        config.collateralCapForGt = collateralCapForGt;

        config.marketConfig = marketConfig;
        config.loanConfig = loanConfig;
        config.underlyingConfig = underlyingConfig;
        config.collateralConfig = collateralConfig;
    }
}
