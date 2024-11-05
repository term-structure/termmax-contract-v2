// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {StateChecker} from "./StateChecker.sol";
import "../../contracts/core/storage/TermMaxStorage.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";

library JSONLoader {
    Vm constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getMarketStateFromJson(
        string memory testdataJSON,
        string memory key
    ) internal pure returns (StateChecker.MarketState memory state) {
        state.apr = vm.parseInt(
            vm.parseJsonString(testdataJSON, string.concat(key, ".apr"))
        );
        state.ftReserve = vm.parseUint(
            vm.parseJsonString(testdataJSON, string.concat(key, ".ftReserve"))
        );
        state.xtReserve = vm.parseUint(
            vm.parseJsonString(testdataJSON, string.concat(key, ".xtReserve"))
        );
        state.lpFtReserve = vm.parseUint(
            vm.parseJsonString(testdataJSON, string.concat(key, ".lpFtReserve"))
        );
        state.lpXtReserve = vm.parseUint(
            vm.parseJsonString(testdataJSON, string.concat(key, ".lpXtReserve"))
        );
        state.underlyingReserve = vm.parseUint(
            vm.parseJsonString(
                testdataJSON,
                string.concat(key, ".underlyingReserve")
            )
        );
        state.collateralReserve = vm.parseUint(
            vm.parseJsonString(
                testdataJSON,
                string.concat(key, ".collateralReserve")
            )
        );
    }

    function getMarketConfigFromJson(
        address treasurer,
        string memory testdataJSON,
        string memory key
    ) internal pure returns (MarketConfig memory marketConfig) {
        marketConfig.openTime = uint64(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".openTime")
                )
            )
        );
        marketConfig.maturity = uint64(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".maturity")
                )
            )
        );
        marketConfig.initialLtv = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".initialLtv")
                )
            )
        );
        marketConfig.apr = int64(
            vm.parseInt(
                vm.parseJsonString(testdataJSON, string.concat(key, ".apr"))
            )
        );
        marketConfig.lsf = uint32(
            vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(key, ".lsf"))
            )
        );
        marketConfig.lendFeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".lendFeeRatio")
                )
            )
        );
        marketConfig.borrowFeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".borrowFeeRatio")
                )
            )
        );
        marketConfig.lockingPercentage = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".lockingPercentage")
                )
            )
        );
        marketConfig.issueFtfeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".issueFtfeeRatio")
                )
            )
        );
        marketConfig.treasurer = treasurer;
        marketConfig.rewardIsDistributed = true;
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
