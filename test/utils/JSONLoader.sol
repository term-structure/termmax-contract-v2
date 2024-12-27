// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {StateChecker} from "./StateChecker.sol";
import "../../contracts/core/storage/TermMaxStorage.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";

library JSONLoader {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getMarketStateFromJson(
        string memory testdataJSON,
        string memory key
    ) internal pure returns (StateChecker.MarketState memory state) {
        state.ftReserve = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".ftReserve")));
        state.xtReserve = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".xtReserve")));
    }

    function getTokenPairConfigFromJson(
        address treasurer,
        string memory testdataJSON,
        string memory key
    ) internal pure returns (TokenPairConfig memory tokenPairConfig) {
        tokenPairConfig.treasurer = treasurer;
        tokenPairConfig.openTime = uint64(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".openTime")))
        );
        tokenPairConfig.maturity = uint64(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".maturity")))
        );
        tokenPairConfig.redeemFeeRatio = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".redeemFeeRatio")))
        );
        tokenPairConfig.issueFtFeeRatio = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".issueFtFeeRatio")))
        );
        tokenPairConfig.protocolFeeRatio = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".protocolFeeRatio")))
        );
    }

    function getMarketConfigFromJson(
        address treasurer,
        string memory testdataJSON,
        string memory key
    ) internal pure returns (MarketConfig memory marketConfig) {
        marketConfig.lendFeeRatio = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".lendFeeRatio")))
        );
        marketConfig.borrowFeeRatio = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".borrowFeeRatio")))
        );
        marketConfig.minNLendFeeR = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".minNLendFeeR")))
        );
        marketConfig.minNBorrowFeeR = uint32(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".minNBorrowFeeR")))
        );
        marketConfig.treasurer = treasurer;
        marketConfig.maker = treasurer;

        string memory curveCutsPath = string.concat(key, ".curveCuts");

        uint length = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".curveCuts.length")));
        marketConfig.borrowCurveCuts = new CurveCut[](length);
        marketConfig.lendCurveCuts = new CurveCut[](length);

        for (uint256 i = 0; i < length; i++) {
            string memory indexPath = string.concat(curveCutsPath, ".", vm.toString(i));
            marketConfig.borrowCurveCuts[i].xtReserve = vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(indexPath, ".xtReserve"))
            );
            marketConfig.borrowCurveCuts[i].liqSquare = vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(indexPath, ".liqSquare"))
            );
            marketConfig.borrowCurveCuts[i].offset = vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(indexPath, ".offset"))
            );

            marketConfig.lendCurveCuts[i].xtReserve = vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(indexPath, ".xtReserve"))
            );
            marketConfig.lendCurveCuts[i].liqSquare = vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(indexPath, ".liqSquare"))
            );
            marketConfig.lendCurveCuts[i].offset = vm.parseUint(
                vm.parseJsonString(testdataJSON, string.concat(indexPath, ".offset"))
            );
        }
    }

    function getRoundDataFromJson(
        string memory testdataJSON,
        string memory key
    ) internal pure returns (MockPriceFeed.RoundData memory priceData) {
        priceData.roundId = uint80(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".roundId"))));
        priceData.answer = vm.parseInt(vm.parseJsonString(testdataJSON, string.concat(key, ".answer")));
        priceData.startedAt = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".startedAt")));
        priceData.updatedAt = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".updatedAt")));
        priceData.answeredInRound = uint80(
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".answeredInRound")))
        );
    }
}
