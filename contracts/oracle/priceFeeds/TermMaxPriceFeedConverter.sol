// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {MathLib} from "contracts/lib/MathLib.sol";

contract TermMaxPriceFeedConverter is ITermMaxPriceFeed {
    using MathLib for *;

    error GetRoundDataNotSupported();

    AggregatorV3Interface public immutable aTokenToBTokenPriceFeed;
    AggregatorV3Interface public immutable bTokenToCTokenPriceFeed;

    int256 immutable priceDemonitor;
    address public immutable asset;

    constructor(address _aTokenToBTokenPriceFeed, address _bTokenToCTokenPriceFeed, address _asset) {
        asset = _asset;
        aTokenToBTokenPriceFeed = AggregatorV3Interface(_aTokenToBTokenPriceFeed);
        bTokenToCTokenPriceFeed = AggregatorV3Interface(_bTokenToCTokenPriceFeed);
        priceDemonitor =
            int256(10 ** aTokenToBTokenPriceFeed.decimals()) * int256(10 ** bTokenToCTokenPriceFeed.decimals());
    }

    function decimals() public view returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        string memory symbol = IERC20Metadata(asset).symbol();
        return string(abi.encodePacked("TermMax price feed: ", symbol, "/USD"));
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
