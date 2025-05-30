// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {StateChecker} from "./StateChecker.sol";
import "contracts/v1/storage/TermMaxStorage.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {DeployUtils} from "./DeployUtils.sol";

library JSONLoader {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getOrderStateFromJson(string memory testdataJSON, string memory key)
        internal
        pure
        returns (StateChecker.OrderState memory state)
    {
        state.ftReserve = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".ftReserve")));
        state.xtReserve = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".xtReserve")));
    }

    function getMarketConfigFromJson(address treasurer, string memory testdataJSON, string memory key)
        internal
        pure
        returns (MarketConfig memory marketConfig)
    {
        marketConfig.treasurer = treasurer;
        marketConfig.maturity = uint64(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".maturity"))));
        marketConfig.feeConfig.mintGtFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".mintGtFeeRatio"))));
        marketConfig.feeConfig.mintGtFeeRef =
            uint32(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".mintGtFeeRef"))));
        marketConfig.feeConfig.lendTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".lendTakerFeeRatio"))));
        marketConfig.feeConfig.borrowTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".borrowTakerFeeRatio"))));
        marketConfig.feeConfig.lendMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".lendMakerFeeRatio"))));
        marketConfig.feeConfig.borrowMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".borrowMakerFeeRatio"))));
    }

    function getOrderConfigFromJson(string memory testdataJSON, string memory key)
        internal
        pure
        returns (OrderConfig memory orderConfig)
    {
        orderConfig.maxXtReserve = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".maxXtReserve")));
        orderConfig.gtId = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".gtId")));

        {
            string memory curveCutsPath = string.concat(key, ".borrowCurveCuts");
            uint256 length =
                vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".borrowCurveCuts.length")));
            orderConfig.curveCuts.borrowCurveCuts = new CurveCut[](length);

            for (uint256 i = 0; i < length; i++) {
                string memory indexPath = string.concat(curveCutsPath, ".", vm.toString(i));
                orderConfig.curveCuts.borrowCurveCuts[i].xtReserve =
                    vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(indexPath, ".xtReserve")));
                orderConfig.curveCuts.borrowCurveCuts[i].liqSquare =
                    vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(indexPath, ".liqSquare")));
                orderConfig.curveCuts.borrowCurveCuts[i].offset =
                    vm.parseInt(vm.parseJsonString(testdataJSON, string.concat(indexPath, ".offset")));
            }
        }
        {
            string memory curveCutsPath = string.concat(key, ".lendCurveCuts");
            uint256 length = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".lendCurveCuts.length")));
            orderConfig.curveCuts.lendCurveCuts = new CurveCut[](length);

            for (uint256 i = 0; i < length; i++) {
                string memory indexPath = string.concat(curveCutsPath, ".", vm.toString(i));
                orderConfig.curveCuts.lendCurveCuts[i].xtReserve =
                    vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(indexPath, ".xtReserve")));
                orderConfig.curveCuts.lendCurveCuts[i].liqSquare =
                    vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(indexPath, ".liqSquare")));
                orderConfig.curveCuts.lendCurveCuts[i].offset =
                    vm.parseInt(vm.parseJsonString(testdataJSON, string.concat(indexPath, ".offset")));
            }
        }
    }

    function getSwapRangeFromJson(string memory testdataJSON, string memory key)
        internal
        pure
        returns (DeployUtils.SwapRange memory swapRange)
    {
        swapRange.buyFtMax = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".buyFtMax")));
        swapRange.buyXtMax = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".buyXtMax")));
        swapRange.sellFtMax = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".sellFtMax")));
        swapRange.sellXtMax = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".sellXtMax")));
        swapRange.buyExactFtMax = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".buyExactFtMax")));
        swapRange.buyExactXtMax = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".buyExactXtMax")));
        swapRange.sellFtForExactTokenMax =
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".sellFtForExactTokenMax")));
        swapRange.sellXtForExactTokenMax =
            vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".sellXtForExactTokenMax")));
    }

    function getRoundDataFromJson(string memory testdataJSON, string memory key)
        internal
        pure
        returns (MockPriceFeed.RoundData memory priceData)
    {
        priceData.roundId = uint80(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".roundId"))));
        priceData.answer = vm.parseInt(vm.parseJsonString(testdataJSON, string.concat(key, ".answer")));
        priceData.startedAt = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".startedAt")));
        priceData.updatedAt = vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".updatedAt")));
        priceData.answeredInRound =
            uint80(vm.parseUint(vm.parseJsonString(testdataJSON, string.concat(key, ".answeredInRound"))));
    }
}
