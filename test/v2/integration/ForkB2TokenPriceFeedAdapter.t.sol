// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxB2TokenPriceFeedAdapter} from "contracts/v2/oracle/adapters/b2/TermMaxB2TokenPriceFeedAdapter.sol";
import {ISupraSValueFeed} from "contracts/v2/oracle/adapters/b2/ISupraSValueFeed.sol";
import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title ForkB2TokenPriceFeedAdapterTest
 * @notice Fork integration test for TermMaxB2TokenPriceFeedAdapter using BTC_USD pair
 */
contract ForkB2TokenPriceFeedAdapterTest is Test {
    using SafeCast for uint256;

    uint256 internal constant MILLISECONDS_PER_SECOND = 1000;

    TermMaxB2TokenPriceFeedAdapter public adapter;
    ISupraSValueFeed public supraSValueFeed;

    // b2-mainnet data provided by user
    uint256 internal constant BTC_USD_INDEX = 18;
    address internal constant SUPRA_SVALUE_FEED = 0xD02cc7a670047b6b012556A88e275c685d25e0c9;

    // keep using existing env key in repo's fork tests
    string internal MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 forkId = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(forkId);

        adapter = new TermMaxB2TokenPriceFeedAdapter(BTC_USD_INDEX, SUPRA_SVALUE_FEED);
        supraSValueFeed = ISupraSValueFeed(SUPRA_SVALUE_FEED);
    }

    function testAdapterInitialization() public view {
        assertEq(adapter.pairIndex(), BTC_USD_INDEX, "pairIndex should match");
        assertEq(address(adapter.supraSValueFeed()), SUPRA_SVALUE_FEED, "value feed address should match");
    }

    function testDecimalsMatchesOracle() public view {
        ISupraSValueFeed.priceFeed memory feed = supraSValueFeed.getSvalue(BTC_USD_INDEX);
        assertEq(adapter.decimals(), uint8(feed.decimals), "adapter decimals should match oracle decimals");
    }

    function testDescription() public view {
        assertEq(adapter.description(), "TermMax B2 Supra SValue Adapter", "description should match");
    }

    function testVersion() public view {
        assertEq(adapter.version(), 1, "version should be 1");
    }

    function testLatestRoundDataMatchesOracle() public view {
        ISupraSValueFeed.priceFeed memory feed = supraSValueFeed.getSvalue(BTC_USD_INDEX);
        uint256 normalizedTime = feed.time / MILLISECONDS_PER_SECOND;

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        assertEq(roundId, uint80(feed.round), "roundId should match oracle round");
        assertEq(answer, feed.price.toInt256(), "answer should match oracle price");
        assertEq(startedAt, normalizedTime, "startedAt should match oracle time in seconds");
        assertEq(updatedAt, normalizedTime, "updatedAt should match oracle time in seconds");
        assertEq(answeredInRound, uint80(feed.round), "answeredInRound should match roundId");

        console.log("Latest BTC/USD price from adapter:", answer);
        console.log("Price decimals:", feed.decimals);
        console.log("Price timestamp (sec):", updatedAt);
        console.log("Price timestamp (ms):", feed.time);
        console.log("Current block timestamp:", block.timestamp);
    }

    function testLatestRoundDataReasonableValues() public view {
        (, int256 answer, uint256 startedAt, uint256 updatedAt,) = adapter.latestRoundData();

        assertGt(answer, 0, "BTC_USD price should be positive");
        assertGt(startedAt, 0, "startedAt should be positive");
        assertGt(updatedAt, 0, "updatedAt should be positive");
        assertEq(startedAt, updatedAt, "startedAt and updatedAt should match");
    }

    function testGetRoundDataReverts() public {
        vm.expectRevert(TermMaxB2TokenPriceFeedAdapter.GetRoundDataNotSupported.selector);
        adapter.getRoundData(1);
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(TermMaxB2TokenPriceFeedAdapter.ZeroAddress.selector);
        new TermMaxB2TokenPriceFeedAdapter(BTC_USD_INDEX, address(0));
    }
}
