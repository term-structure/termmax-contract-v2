// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MathLib} from "contracts/v1/lib/MathLib.sol";

contract PriceFeedConverter is AggregatorV3Interface {
    using MathLib for *;

    error GetRoundDataNotSupported();

    AggregatorV3Interface public immutable aTokenToBTokenPriceFeed;
    AggregatorV3Interface public immutable bTokenToCTokenPriceFeed;

    int256 immutable priceDemonitor;

    constructor(address _aTokenToBTokenPriceFeed, address _bTokenToCTokenPriceFeed) {
        aTokenToBTokenPriceFeed = AggregatorV3Interface(_aTokenToBTokenPriceFeed);
        bTokenToCTokenPriceFeed = AggregatorV3Interface(_bTokenToCTokenPriceFeed);
        priceDemonitor =
            int256(10 ** aTokenToBTokenPriceFeed.decimals()) * int256(10 ** bTokenToCTokenPriceFeed.decimals());
    }

    function decimals() public view returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        return string(
            abi.encodePacked(aTokenToBTokenPriceFeed.description(), " - ", bTokenToCTokenPriceFeed.description())
        );
    }

    function version() external view returns (uint256) {
        return aTokenToBTokenPriceFeed.version().min(bTokenToCTokenPriceFeed.version());
    }

    function getRoundData(uint80 /* _roundId */ )
        external
        view
        returns (
            uint80, /* roundId */
            int256, /* answer */
            uint256, /* startedAt */
            uint256, /* updatedAt */
            uint80 /* answeredInRound */
        )
    {
        // error to call this function because cannot get the chi (rate accumulator) at a specific round
        revert GetRoundDataNotSupported();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            aTokenToBTokenPriceFeed.latestRoundData();
        (, int256 answer2, uint256 startedAt2, uint256 updatedAt2,) = bTokenToCTokenPriceFeed.latestRoundData();
        // tokenPrice = answer * answer2
        answer = answer * answer2 * int256((10 ** decimals())) / priceDemonitor;
        return (roundId, answer, startedAt.min(startedAt2), updatedAt.min(updatedAt2), answeredInRound);
    }
}
