// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MarketConfig, FeeConfig, LoanConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {VaultInitialParamsV2, IERC20, IERC4626} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {IOracleV2, AggregatorV3Interface} from "contracts/v2/oracle/OracleAggregatorV2.sol";

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

    enum PriceFeedType {
        PriceFeedWithERC4626,
        PriceFeedConverter,
        PTWithPriceFeed,
        ConstantPriceFeed
    }

    struct PriceFeedDeployParams {
        PriceFeedType priceFeedType;
        address underlyingPriceFeed; // for PriceFeedWithERC4626 or PTWithPriceFeed
        address priceFeed1; // for PriceFeedConverter
        address priceFeed2; // for PriceFeedConverter
        address pendlePYLpOracle; // for PTWithPriceFeed
        address market; // for PTWithPriceFeed
        uint32 duration; // for PTWithPriceFeed
        int256 constantPrice; // for ConstantPriceFeed
    }

    struct OracleConfig {
        address asset;
        bool needsDeployment;
        PriceFeedDeployParams deployFeedParams;
        IOracleV2.Oracle oracleParams;
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

    struct PoolConfig {
        address asset;
        address thirdPool;
        StakingBuffer.BufferConfig bufferConfig;
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

    function getVaultConfigsFromJson(string memory jsonData)
        internal
        pure
        returns (VaultInitialParamsV2[] memory initialParamsList)
    {
        uint256 configNum = uint256(vm.parseUint(vm.parseJsonString(jsonData, ".configNum")));
        initialParamsList = new VaultInitialParamsV2[](configNum);
        for (uint256 i; i < configNum; i++) {
            VaultInitialParamsV2 memory initialParams = getVaultConfigFromJson(jsonData, i);
            initialParamsList[i] = initialParams;
        }
    }

    function getVaultConfigFromJson(string memory jsonData, uint256 index)
        internal
        pure
        returns (VaultInitialParamsV2 memory initialParams)
    {
        string memory configPrefix = string.concat(".configs.configs_", vm.toString(index));
        initialParams.curator = jsonData.readAddress(string.concat(configPrefix, ".curator"));
        initialParams.guardian = jsonData.readAddress(string.concat(configPrefix, ".guardian"));
        initialParams.timelock = uint64(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".timelock"))));
        initialParams.asset = IERC20(jsonData.readAddress(string.concat(configPrefix, ".asset")));
        initialParams.pool = IERC4626(jsonData.readAddress(string.concat(configPrefix, ".pool")));
        initialParams.maxCapacity =
            uint256(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".maxCapacity"))));
        initialParams.name = jsonData.readString(string.concat(configPrefix, ".name"));
        initialParams.symbol = jsonData.readString(string.concat(configPrefix, ".symbol"));
        initialParams.performanceFeeRate =
            uint32(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".performanceFeeRate"))));
        initialParams.minApy = uint32(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".minApy"))));
    }

    function getPoolConfigsFromJson(string memory jsonData) internal view returns (PoolConfig[] memory poolConfigs) {
        uint256 configNum = uint256(vm.parseUint(vm.parseJsonString(jsonData, ".configNum")));
        poolConfigs = new PoolConfig[](configNum);
        for (uint256 i; i < configNum; i++) {
            PoolConfig memory poolConfig = getPoolConfigFromJson(jsonData, i);
            poolConfigs[i] = poolConfig;
        }
    }

    function getPoolConfigFromJson(string memory jsonData, uint256 index)
        internal
        view
        returns (PoolConfig memory poolConfig)
    {
        string memory configPrefix = string.concat(".configs.configs_", vm.toString(index));
        if (vm.keyExistsJson(jsonData, string.concat(configPrefix, ".thirdPool"))) {
            poolConfig.thirdPool = jsonData.readAddress(string.concat(configPrefix, ".thirdPool"));
        }
        if (vm.keyExistsJson(jsonData, string.concat(configPrefix, ".asset"))) {
            poolConfig.asset = jsonData.readAddress(string.concat(configPrefix, ".asset"));
        }
        StakingBuffer.BufferConfig memory bufferConfig;
        bufferConfig.minimumBuffer =
            uint256(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".bufferConfig.minimumBuffer"))));
        bufferConfig.maximumBuffer =
            uint256(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".bufferConfig.maximumBuffer"))));
        bufferConfig.buffer =
            uint256(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".bufferConfig.buffer"))));
        poolConfig.bufferConfig = bufferConfig;
    }

    function getOracleConfigsFromJson(string memory jsonData)
        internal
        pure
        returns (OracleConfig[] memory oracleConfigs)
    {
        uint256 configNum = uint256(vm.parseUint(vm.parseJsonString(jsonData, ".configNum")));
        oracleConfigs = new OracleConfig[](configNum);
        for (uint256 i; i < configNum; i++) {
            OracleConfig memory oracleConfig = getOracleConfigFromJson(jsonData, i);
            oracleConfigs[i] = oracleConfig;
        }
    }

    function getOracleConfigFromJson(string memory jsonData, uint256 index)
        internal
        pure
        returns (OracleConfig memory oracleConfig)
    {
        string memory configPrefix = string.concat(".configs.configs_", vm.toString(index));
        oracleConfig.asset = jsonData.readAddress(string.concat(configPrefix, ".asset"));
        oracleConfig.needsDeployment =
            vm.parseBool(jsonData.readString(string.concat(configPrefix, ".needsDeployment")));
        if (!oracleConfig.needsDeployment) {
            oracleConfig.oracleParams.aggregator =
                AggregatorV3Interface(jsonData.readAddress(string.concat(configPrefix, ".oracleParams.aggregator")));
            oracleConfig.oracleParams.backupAggregator = AggregatorV3Interface(
                jsonData.readAddress(string.concat(configPrefix, ".oracleParams.backupAggregator"))
            );
            oracleConfig.oracleParams.backupHeartbeat =
                uint32(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".oracleParams.backupHeartbeat"))));
        } else {
            oracleConfig.deployFeedParams.priceFeedType = PriceFeedType(
                uint8(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".deployFeedParams.priceFeedType"))))
            );
            if (oracleConfig.deployFeedParams.priceFeedType == PriceFeedType.PriceFeedWithERC4626) {
                oracleConfig.deployFeedParams.underlyingPriceFeed =
                    jsonData.readAddress(string.concat(configPrefix, ".deployFeedParams.underlyingPriceFeed"));
            } else if (oracleConfig.deployFeedParams.priceFeedType == PriceFeedType.PriceFeedConverter) {
                oracleConfig.deployFeedParams.priceFeed1 =
                    jsonData.readAddress(string.concat(configPrefix, ".deployFeedParams.priceFeed1"));
                oracleConfig.deployFeedParams.priceFeed2 =
                    jsonData.readAddress(string.concat(configPrefix, ".deployFeedParams.priceFeed2"));
            } else if (oracleConfig.deployFeedParams.priceFeedType == PriceFeedType.PTWithPriceFeed) {
                oracleConfig.deployFeedParams.underlyingPriceFeed =
                    jsonData.readAddress(string.concat(configPrefix, ".deployFeedParams.underlyingPriceFeed"));
                oracleConfig.deployFeedParams.pendlePYLpOracle =
                    jsonData.readAddress(string.concat(configPrefix, ".deployFeedParams.pendlePYLpOracle"));
                oracleConfig.deployFeedParams.market =
                    jsonData.readAddress(string.concat(configPrefix, ".deployFeedParams.market"));
                oracleConfig.deployFeedParams.duration =
                    uint32(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".deployFeedParams.duration"))));
            } else if (oracleConfig.deployFeedParams.priceFeedType == PriceFeedType.ConstantPriceFeed) {
                oracleConfig.deployFeedParams.constantPrice =
                    vm.parseInt(jsonData.readString(string.concat(configPrefix, ".deployFeedParams.constantPrice")));
            }
        }
        oracleConfig.oracleParams.heartbeat =
            uint32(vm.parseUint(jsonData.readString(string.concat(configPrefix, ".oracleParams.heartbeat"))));
        oracleConfig.oracleParams.maxPrice =
            vm.parseInt(jsonData.readString(string.concat(configPrefix, ".oracleParams.maxPrice")));
        oracleConfig.oracleParams.minPrice =
            vm.parseInt(jsonData.readString(string.concat(configPrefix, ".oracleParams.minPrice")));
        return oracleConfig;
    }
}
