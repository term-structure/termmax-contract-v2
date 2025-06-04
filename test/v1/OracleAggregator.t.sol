// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {OracleAggregator} from "contracts/v1/oracle/OracleAggregator.sol";
import {AggregatorV3Interface, IOracle} from "contracts/v1/oracle/IOracle.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";

contract OracleAggregatorTest is Test {
    OracleAggregator public oracleAggregator;
    MockPriceFeed public primaryFeed;
    MockPriceFeed public backupFeed;

    address public constant OWNER = address(0x1);
    address public constant ASSET = address(0x2);
    uint256 public constant TIMELOCK = 1 days;
    uint32 public constant HEARTBEAT = 1 hours;

    // Price feed configuration
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 3000e8;

    function setUp() public {
        // Deploy mock price feeds
        primaryFeed = new MockPriceFeed(OWNER);
        backupFeed = new MockPriceFeed(OWNER);

        // Set initial price data
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: INITIAL_PRICE,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });

        vm.startPrank(OWNER);
        primaryFeed.updateRoundData(roundData);
        backupFeed.updateRoundData(roundData);
        vm.stopPrank();

        // Deploy OracleAggregator with owner and timelock
        vm.prank(OWNER);
        oracleAggregator = new OracleAggregator(OWNER, TIMELOCK);
    }

    function test_SubmitPendingOracle() public {
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);

        (AggregatorV3Interface aggregator, AggregatorV3Interface backupAgg, uint32 heartbeat) =
            oracleAggregator.oracles(ASSET);
        assertEq(address(aggregator), address(0), "Oracle should not be set yet");
        assertEq(address(backupAgg), address(0), "Backup oracle should not be set yet");
        assertEq(heartbeat, 0, "Heartbeat should not be set yet");

        (IOracle.Oracle memory pendingOracle, uint64 validAt) = oracleAggregator.pendingOracles(ASSET);
        assertEq(address(pendingOracle.aggregator), address(primaryFeed));
        assertEq(address(pendingOracle.backupAggregator), address(backupFeed));
        assertEq(pendingOracle.heartbeat, HEARTBEAT);
        assertEq(validAt, block.timestamp + TIMELOCK);
    }

    function test_AcceptPendingOracle() public {
        // Submit pending oracle
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);

        // Warp time past timelock
        vm.warp(block.timestamp + TIMELOCK + 1);

        oracleAggregator.acceptPendingOracle(ASSET);

        (AggregatorV3Interface aggregator, AggregatorV3Interface backupAgg, uint32 heartbeat) =
            oracleAggregator.oracles(ASSET);
        assertEq(address(aggregator), address(primaryFeed));
        assertEq(address(backupAgg), address(backupFeed));
        assertEq(heartbeat, HEARTBEAT);

        // Verify pending oracle is cleared
        (IOracle.Oracle memory pendingOracle, uint64 validAt) = oracleAggregator.pendingOracles(ASSET);
        assertEq(address(pendingOracle.aggregator), address(0));
        assertEq(address(pendingOracle.backupAggregator), address(0));
        assertEq(pendingOracle.heartbeat, 0);
        assertEq(validAt, 0);
    }

    function test_GetPrice_PrimaryOracle() public {
        // Setup oracle
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Update primary oracle timestamp to match current time
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: INITIAL_PRICE,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });
        vm.prank(OWNER);
        primaryFeed.updateRoundData(roundData);

        // Get price
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(INITIAL_PRICE));
        assertEq(decimals, DECIMALS);
    }

    function test_GetPrice_FallbackToBackup() public {
        // Setup oracle
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Make primary oracle stale
        vm.warp(block.timestamp + HEARTBEAT + 1);

        // Update backup price
        int256 backupPrice = 3100e8;
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: backupPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        vm.prank(OWNER);
        backupFeed.updateRoundData(roundData);

        // Get price - should use backup
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(backupPrice));
        assertEq(decimals, DECIMALS);
    }

    function test_RevertGetPrice_BothOraclesStale() public {
        // Setup oracle
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Make both oracles stale
        vm.warp(block.timestamp + HEARTBEAT + 1);

        vm.expectRevert(abi.encodeWithSignature("OracleIsNotWorking(address)", ASSET));
        // Should revert
        oracleAggregator.getPrice(ASSET);
    }

    function test_RevertSubmitPendingOracle_NotOwner() public {
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.prank(address(0x3));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0x3)));
        oracleAggregator.submitPendingOracle(ASSET, oracle);
    }

    function test_RevertAcceptPendingOracle_BeforeTimelock() public {
        // Submit pending oracle
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.expectRevert(abi.encodeWithSignature("TimelockNotElapsed()"));
        // Try to accept before timelock expires
        oracleAggregator.acceptPendingOracle(ASSET);
    }

    function test_RemoveOracle() public {
        // First add an oracle
        IOracle.Oracle memory oracle =
            IOracle.Oracle({aggregator: primaryFeed, backupAggregator: backupFeed, heartbeat: HEARTBEAT});

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Now remove it by submitting empty oracle
        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(
            ASSET,
            IOracle.Oracle({
                aggregator: AggregatorV3Interface(address(0)),
                backupAggregator: AggregatorV3Interface(address(0)),
                heartbeat: 0
            })
        );

        // Verify oracle is removed
        (AggregatorV3Interface aggregator, AggregatorV3Interface backupAgg, uint32 heartbeat) =
            oracleAggregator.oracles(ASSET);
        assertEq(address(aggregator), address(0));
        assertEq(address(backupAgg), address(0));
        assertEq(heartbeat, 0);
    }
}
