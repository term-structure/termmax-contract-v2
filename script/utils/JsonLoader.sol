// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
// import "../../contracts/core/storage/TermMaxStorage.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";

library JSONLoader {
    struct MarketConfig {
        uint256 openTime;
        uint256 maturity;
        uint256 initialLtv;
        uint256 apr;
        uint256 lsf;
        uint256 lendFeeRatio;
        uint256 borrowFeeRatio;
        uint256 issueFtFeeRatio;
        uint256 lockingPercentage;
        uint256 protocolFeeRatio;
        uint256 minNLendFeeR;
        uint256 minNBorrowFeeR;
        uint256 maxLtv;
        uint256 liquidationLtv;
        bool liquidatable;
        address treasurer;
    }

    struct UnderlyingConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialPrice;
    }

    struct CollateralConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialPrice;
    }

    struct Config {
        MarketConfig marketConfig;
        UnderlyingConfig underlyingConfig;
        CollateralConfig collateralConfig;
    }

    Vm constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run(string memory path) public {
        // Load the JSON file content as a string
        string memory jsonContent = vm.readFile(path);

        // Parse the JSON array
        bytes memory rawData = vm.parseJson(jsonContent);

        // Decode the array into Config structs
        Config[] memory configs = abi.decode(rawData, (Config[]));

        // Log the data for verification
        for (uint i = 0; i < configs.length; i++) {
            console.log(
                "MarketConfig Open Time:",
                configs[i].marketConfig.openTime
            );
            console.log(
                "Underlying Symbol:",
                configs[i].underlyingConfig.symbol
            );
            console.log("Collateral Name:", configs[i].collateralConfig.name);
        }
    }

    function decodeConfig(
        string memory jsonData
    ) public pure returns (MarketConfig[] memory) {
        bytes memory data = vm.parseJson(jsonData, ".marketConfig");
        MarketConfig[] memory configs = abi.decode(data, (MarketConfig[]));
        console.log("openTime: ", configs[0].openTime);
        console.log("maturity: ", configs[0].maturity);
        console.log("initialLtv: ", configs[0].initialLtv);
        console.log("apr: ", configs[0].apr);
        console.log("lsf: ", configs[0].lsf);
        console.log("lendFeeRatio: ", configs[0].lendFeeRatio);
        console.log("borrowFeeRatio: ", configs[0].borrowFeeRatio);
        console.log("issueFtFeeRatio: ", configs[0].issueFtFeeRatio);
        console.log("lockingPercentage: ", configs[0].lockingPercentage);
        console.log("protocolFeeRatio: ", configs[0].protocolFeeRatio);
        console.log("minNLendFeeR: ", configs[0].minNLendFeeR);
        console.log("minNBorrowFeeR: ", configs[0].minNBorrowFeeR);
        console.log("maxLtv: ", configs[0].maxLtv);
        console.log("liquidationLtv: ", configs[0].liquidationLtv);
        console.log("liquidatable: ", configs[0].liquidatable);
        console.log("treasurer: ", configs[0].treasurer);
        return configs;
    }

    function getConfigFromJson(
        string memory jsonData
    ) internal pure returns (Config memory config) {
        // config.marketConfig.openTime = uint64(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".openTime")
        //         )
        //     )
        // );
        // config.marketConfig.maturity = uint64(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".maturity")
        //         )
        //     )
        // );
        // config.marketConfig.initialLtv = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".initialLtv")
        //         )
        //     )
        // );
        // config.marketConfig.apr = int64(
        //     vm.parseInt(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".apr")
        //         )
        //     )
        // );
        // config.marketConfig.lsf = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".lsf")
        //         )
        //     )
        // );
        // config.marketConfig.lendFeeRatio = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".lendFeeRatio")
        //         )
        //     )
        // );
        // config.marketConfig.borrowFeeRatio = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".borrowFeeRatio")
        //         )
        //     )
        // );
        // config.marketConfig.lockingPercentage = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".lockingPercentage")
        //         )
        //     )
        // );
        // config.marketConfig.issueFtFeeRatio = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".issueFtFeeRatio")
        //         )
        //     )
        // );
        // config.marketConfig.minNLendFeeR = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".minNLendFeeR")
        //         )
        //     )
        // );
        // config.marketConfig.minNBorrowFeeR = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".minNBorrowFeeR")
        //         )
        //     )
        // );
        // config.marketConfig.protocolFeeRatio = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".protocolFeeRatio")
        //         )
        //     )
        // );
        // config.marketConfig.treasurer = address(
        //     vm.parseAddress(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".treasurer")
        //         )
        //     )
        // );
        // config.maxLtv = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".maxLtv")
        //         )
        //     )
        // );
        // config.liquidationLtv = uint32(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".liquidationLtv")
        //         )
        //     )
        // );
        // config.liquidatable = bool(
        //     vm.parseBool(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(".marketConfig", ".liquidatable")
        //         )
        //     )
        // );
        // config.underlyingConfig.name = vm.parseJsonString(
        //     jsonData,
        //     string.concat(".marketConfig", ".underlyingConfig", ".name")
        // );
        // config.underlyingConfig.symbol = vm.parseJsonString(
        //     jsonData,
        //     string.concat(".marketConfig", ".underlyingConfig", ".symbol")
        // );
        // config.underlyingConfig.decimals = uint8(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(
        //                 ".marketConfig",
        //                 ".underlyingConfig",
        //                 ".decimals"
        //             )
        //         )
        //     )
        // );
        // config.underlyingConfig.initialPrice = int256(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(
        //                 ".marketConfig",
        //                 ".underlyingConfig",
        //                 ".initialPrice"
        //             )
        //         )
        //     )
        // );
        // config.collateralConfig.name = vm.parseJsonString(
        //     jsonData,
        //     string.concat(".marketConfig", ".collateralConfig", ".name")
        // );
        // config.collateralConfig.symbol = vm.parseJsonString(
        //     jsonData,
        //     string.concat(".marketConfig", ".collateralConfig", ".symbol")
        // );
        // config.collateralConfig.decimals = uint8(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(
        //                 ".marketConfig",
        //                 ".collateralConfig",
        //                 ".decimals"
        //             )
        //         )
        //     )
        // );
        // config.collateralConfig.initialPrice = int256(
        //     vm.parseUint(
        //         vm.parseJsonString(
        //             jsonData,
        //             string.concat(
        //                 ".marketConfig",
        //                 ".collateralConfig",
        //                 ".initialPrice"
        //             )
        //         )
        //     )
        // );
    }

    function getRoundDataFromJson(
        string memory testdataJSON,
        string memory key
    ) internal pure returns (MockPriceFeed.RoundData memory priceData) {
        priceData.roundId = uint80(
            vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(key, ".roundId"))
            )
        );
        priceData.answer = vm.parseInt(
            vm.parseJsonString(testdataJSON, string.concat(key, ".answer"))
        );
        priceData.startedAt = vm.parseUint(
            vm.parseJsonString(testdataJSON, string.concat(key, ".startedAt"))
        );
        priceData.updatedAt = vm.parseUint(
            vm.parseJsonString(testdataJSON, string.concat(key, ".updatedAt"))
        );
        priceData.answeredInRound = uint80(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".answeredInRound")
                )
            )
        );
    }
}
