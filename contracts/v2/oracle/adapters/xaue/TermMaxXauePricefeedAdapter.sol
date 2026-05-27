// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IXaueOracle {
    function getLatestPrice() external view returns (uint256 price);
    function lastUpdateTimestamp() external view returns (uint256 timestamp);
}

/**
 * @title TermMaxXauePricefeedAdapter
 * @notice Adapter that wraps XAUE oracle to provide Chainlink AggregatorV3Interface
 */
contract TermMaxXauePricefeedAdapter is AggregatorV3Interface {
    using SafeCast for *;

    IXaueOracle public constant xaueOracle = IXaueOracle(0x0618BD112C396060d2b37B537b3d92e757644169);

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function description() external view override returns (string memory) {
        return "TermMax price feed: XAUE/XAUT";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        revert("GetRoundDataNotSupported");
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        uint256 timestamp = xaueOracle.lastUpdateTimestamp();
        int256 answer = xaueOracle.getLatestPrice().toInt256();
        // For simplicity, we return the same timestamp for startedAt and updatedAt, and set roundId and answeredInRound to 1
        return (1, answer, timestamp, timestamp, 1);
    }
}
