// filepath: /Users/evan/Documents/tkspring/termmax-contract/test/v2/oracle/OracleAggregatorWithSequencerV2.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {OracleAggregatorWithSequencerV2} from "contracts/v2/oracle/OracleAggregatorWithSequencerV2.sol";
import {OracleAggregatorV2, IOracleV2, AggregatorV3Interface} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {MockPriceFeedV2} from "contracts/v2/test/MockPriceFeedV2.sol";

contract OracleAggregatorWithSequencerTestV2 is Test {
    OracleAggregatorWithSequencerV2 public oracleWithSequencer;
    MockPriceFeedV2 public primaryFeed;
    MockPriceFeedV2 public backupFeed;
    MockPriceFeedV2 public sequencerFeed;

    address public constant OWNER = address(0x1);
    address public constant ASSET = address(0x2);
    uint256 public constant TIMELOCK = 0; // use 0 for simpler testing

    int256 public constant INITIAL_PRICE = 3000e8;
    uint8 public constant DECIMALS = 8;

    function setUp() public {
        // Deploy mock price feeds
        primaryFeed = new MockPriceFeedV2(OWNER);
        backupFeed = new MockPriceFeedV2(OWNER);
        sequencerFeed = new MockPriceFeedV2(OWNER);

        // Set initial price data for primary/backup
        MockPriceFeedV2.RoundData memory p = MockPriceFeedV2.RoundData({
            roundId: 1,
            answer: INITIAL_PRICE,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });

        vm.startPrank(OWNER);
        primaryFeed.updateRoundData(p);
        backupFeed.updateRoundData(p);
        vm.stopPrank();
    }

    function test_RevertWhenSequencerDown() public {
        // Sequencer reports down (answer == 1)
        MockPriceFeedV2.RoundData memory seqDown = MockPriceFeedV2.RoundData({
            roundId: 1,
            answer: 1,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });

        vm.prank(OWNER);
        sequencerFeed.updateRoundData(seqDown);

        // Deploy oracle aggregator with sequencer feed and small grace period
        uint256 grace = 60;
        vm.prank(OWNER);
        oracleWithSequencer = new OracleAggregatorWithSequencerV2(OWNER, TIMELOCK, address(sequencerFeed), grace);

        // Any getPrice should revert with SequencerIsDown before oracle checks
        vm.expectRevert(abi.encodeWithSignature("SequencerIsDown()"));
        oracleWithSequencer.getPrice(ASSET);
    }

    function test_RevertWhenGracePeriodNotOver() public {
        // Sequencer reports up (answer == 0) but startedAt is now -> grace period not over
        MockPriceFeedV2.RoundData memory seqUpRecent = MockPriceFeedV2.RoundData({
            roundId: 1,
            answer: 0,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });

        vm.prank(OWNER);
        sequencerFeed.updateRoundData(seqUpRecent);

        uint256 grace = 120; // 2 minutes
        vm.prank(OWNER);
        oracleWithSequencer = new OracleAggregatorWithSequencerV2(OWNER, TIMELOCK, address(sequencerFeed), grace);

        // Even if oracle mapping is not set, sequencer check runs first and should revert due to grace
        vm.expectRevert(abi.encodeWithSignature("SequencerIsDown()"));
        oracleWithSequencer.getPrice(ASSET);
    }

    function test_GetPriceSucceedsAfterGracePeriod() public {
        // Sequencer reports up, but startedAt is set sufficiently in the past so grace period is over
        uint256 grace = 100;
        // ensure current timestamp is large enough to subtract without underflow
        vm.warp(block.timestamp + grace + 100);
        // set startedAt to past so block.timestamp - startedAt > grace
        uint256 startedAt = block.timestamp - (grace + 10);

        MockPriceFeedV2.RoundData memory seqUpOld = MockPriceFeedV2.RoundData({
            roundId: 2,
            answer: 0,
            startedAt: startedAt,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });

        vm.prank(OWNER);
        sequencerFeed.updateRoundData(seqUpOld);

        vm.prank(OWNER);
        oracleWithSequencer = new OracleAggregatorWithSequencerV2(OWNER, TIMELOCK, address(sequencerFeed), grace);

        // Configure an asset oracle and activate it (timelock = 0)
        IOracleV2.Oracle memory cfg = IOracleV2.Oracle({
            aggregator: primaryFeed,
            backupAggregator: AggregatorV3Interface(address(0)),
            heartbeat: 0,
            backupHeartbeat: 0,
            maxPrice: 0,
            minPrice: 0
        });

        vm.prank(OWNER);
        oracleWithSequencer.submitPendingOracle(ASSET, cfg);
        // accept immediately because TIMELOCK == 0
        oracleWithSequencer.acceptPendingOracle(ASSET);

        // Update primary feed to have current round data
        MockPriceFeedV2.RoundData memory p = MockPriceFeedV2.RoundData({
            roundId: 3,
            answer: INITIAL_PRICE,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 3
        });
        vm.prank(OWNER);
        primaryFeed.updateRoundData(p);

        (uint256 price, uint8 decimals) = oracleWithSequencer.getPrice(ASSET);
        assertEq(price, uint256(INITIAL_PRICE));
        assertEq(decimals, DECIMALS);
    }
}
