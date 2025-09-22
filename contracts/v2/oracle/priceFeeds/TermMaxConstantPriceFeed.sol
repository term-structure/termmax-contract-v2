// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {VersionV2} from "../../VersionV2.sol";

contract TermMaxConstantPriceFeed is ITermMaxPriceFeed, VersionV2 {
    AggregatorV3Interface public immutable assetPriceFeed;
    int256 private immutable result;

    constructor(int256 _result) {
        result = _result;
    }

    function decimals() external view override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        return "TermMax Constant price feed";
    }

    function version() external view override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId) external view override returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        answer = int256(result);
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 1;
    }

    function latestRoundData() external view override returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        answer = int256(result);
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 1;
    }

    function asset() external view override returns (address) {
        return address(0);
    }
}
