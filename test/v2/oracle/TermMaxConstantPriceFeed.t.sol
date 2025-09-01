// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxConstantPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxConstantPriceFeed.sol";

contract TermMaxConstantPriceFeedTest is Test {
    TermMaxConstantPriceFeed public feed;

    int256 public constant INITIAL_PRICE = 3000e8;

    function setUp() public {
        feed = new TermMaxConstantPriceFeed(INITIAL_PRICE);
    }

    function testDecimals() public view {
        assertEq(feed.decimals(), 8);
    }

    function testDescription() public view {
        assertEq(feed.description(), "TermMax Constant price feed");
    }

    function testVersion() public view {
        assertEq(feed.version(), 1);
    }

    function testLatestRoundDataReturnsConstantAnswerAndTimestamps() public view {
        (, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        assertEq(answer, INITIAL_PRICE);
        assertEq(answeredInRound, 1);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        // roundId is intentionally ignored by the feed implementation
    }

    function testGetRoundDataReturnsSameAsLatest() public view {
        (, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = feed.getRoundData(42);

        assertEq(answer, INITIAL_PRICE);
        assertEq(answeredInRound, 1);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
    }

    function testAssetIsZeroAddress() public view {
        assertEq(feed.asset(), address(0));
    }
}
