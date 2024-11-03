// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {StateChecker} from "./StateChecker.sol";
import {TermMaxStorage} from "../../contracts/core/storage/TermMaxStorage.sol";

library JSONLoader {
    Vm constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getMarketStateFromJson(
        string memory testdataJSON,
        string memory key
    ) internal view returns (StateChecker.MarketState memory state) {
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
    ) internal view returns (TermMaxStorage.MarketConfig memory marketConfig) {
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
        marketConfig.lockingFeeRatio = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".lockingFeeRatio")
                )
            )
        );
        marketConfig.minLeveragedXt = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".minLeveragedXt")
                )
            )
        );
        marketConfig.minLeveredFt = uint32(
            vm.parseUint(
                vm.parseJsonString(
                    testdataJSON,
                    string.concat(key, ".minLeveredFt")
                )
            )
        );
        marketConfig.treasurer = treasurer;
        marketConfig.rewardIsDistributed = true;
    }
}
