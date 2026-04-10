// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ITermMaxPriceFeed, AggregatorV3Interface} from "../../priceFeeds/ITermMaxPriceFeed.sol";
import {IPharosOracle} from "./IPharosOracle.sol";

/**
 * @title TermMaxPharosPriceFeedAdapter
 * @notice Adapter that wraps a Pharos oracle to provide Chainlink AggregatorV3Interface
 * @dev Converts Pharos's latestAnswer()/latestTimestamp() to Chainlink's latestRoundData() format.
 *      latestTimestamp() is used as both the round ID and updatedAt value.
 */
contract TermMaxPharosPriceFeedAdapter is ITermMaxPriceFeed {
    error GetRoundDataNotSupported();

    IPharosOracle public immutable pharosOracle;
    address public immutable override asset;

    /**
     * @notice Construct the Pharos price feed adapter
     * @param _pharosOracle The Pharos oracle contract address
     * @param _asset The asset whose price is provided by this oracle
     */
    constructor(address _pharosOracle, address _asset) {
        pharosOracle = IPharosOracle(_pharosOracle);
        asset = _asset;
    }

    /**
     * @notice Returns the number of decimals used by this price feed, sourced from the Pharos oracle
     */
    function decimals() external view override returns (uint8) {
        return pharosOracle.decimals();
    }

    /**
     * @notice Returns a human-readable description of this price feed
     */
    function description() external view override returns (string memory) {
        return string(abi.encodePacked("TermMax Pharos adapter: ", IERC20Metadata(asset).symbol(), "/USD"));
    }

    /**
     * @notice Returns version 1
     */
    function version() external pure override returns (uint256) {
        return 1;
    }

    /**
     * @notice Not supported — Pharos oracle does not provide historical round data
     */
    function getRoundData(uint80 /* _roundId */ )
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert GetRoundDataNotSupported();
    }

    /**
     * @notice Get the latest price data from the Pharos oracle
     * @return roundId The latest timestamp cast to uint80, used as the round identifier
     * @return answer The latest price answer
     * @return startedAt The latest timestamp
     * @return updatedAt The latest timestamp
     * @return answeredInRound Same as roundId
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 updateTime = pharosOracle.latestTimestamp();
        return (uint80(updateTime), pharosOracle.latestAnswer(), updateTime, updateTime, uint80(updateTime));
    }
}
