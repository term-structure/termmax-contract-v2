// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISupraSValueFeed} from "./ISupraSValueFeed.sol";

/**
 * @title TermMaxB2TokenPriceFeedAdapter
 * @notice Adapter that wraps B2 Supra SValue feed and exposes Chainlink AggregatorV3Interface
 */
contract TermMaxB2TokenPriceFeedAdapter is AggregatorV3Interface {
    using SafeCast for uint256;

    error GetRoundDataNotSupported();
    error ZeroAddress();

    uint256 internal constant MILLISECONDS_PER_SECOND = 1000;

    ISupraSValueFeed public immutable supraSValueFeed;
    uint256 public immutable pairIndex;

    /**
     * @param _pairIndex Supra pair index
     * @param _supraSValueFeed Supra SValue feed contract address
     */
    constructor(uint256 _pairIndex, address _supraSValueFeed) {
        if (_supraSValueFeed == address(0)) revert ZeroAddress();
        pairIndex = _pairIndex;
        supraSValueFeed = ISupraSValueFeed(_supraSValueFeed);
    }

    function decimals() external view override returns (uint8) {
        ISupraSValueFeed.priceFeed memory feed = supraSValueFeed.getSvalue(pairIndex);
        return feed.decimals.toUint8();
    }

    function description() external pure override returns (string memory) {
        return "TermMax B2 Supra SValue Adapter";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 /* _roundId */ )
        external
        pure
        override
        returns (
            uint80, /* roundId */
            int256, /* answer */
            uint256, /* startedAt */
            uint256, /* updatedAt */
            uint80 /* answeredInRound */
        )
    {
        revert GetRoundDataNotSupported();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        ISupraSValueFeed.priceFeed memory feed = supraSValueFeed.getSvalue(pairIndex);

        roundId = feed.round.toUint80();
        answer = feed.price.toInt256();
        // Supra time is returned in milliseconds, normalize to seconds for AggregatorV3 compatibility
        uint256 normalizedTime = feed.time / MILLISECONDS_PER_SECOND;
        startedAt = normalizedTime;
        updatedAt = normalizedTime;
        answeredInRound = roundId;
    }
}
