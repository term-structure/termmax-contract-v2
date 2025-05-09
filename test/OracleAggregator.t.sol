// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {OracleAggregator} from "../contracts/oracle/OracleAggregator.sol";
import {AggregatorV3Interface, IOracle} from "../contracts/oracle/IOracle.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";

contract OracleAggregatorTest is Test {
    OracleAggregator public oracleAggregator;
    MockPriceFeed public primaryFeed;
    MockPriceFeed public backupFeed;

    address public constant OWNER = address(0x1);
    address public constant ASSET = address(0x2);
    uint256 public constant TIMELOCK = 1 days;
    uint32 public constant HEARTBEAT = 1 hours;
    uint32 public constant BACKUP_HEARTBEAT = 2 hours;
    int256 public constant MAX_PRICE = 10000e8;

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
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);

        // Access the Oracle struct directly from the mapping
        (
            AggregatorV3Interface aggregator,
            AggregatorV3Interface backupAggregator,
            int256 maxPrice,
            uint32 heartbeat,
            uint32 backupHeartbeat
        ) = oracleAggregator.oracles(ASSET);
        assertEq(address(aggregator), address(0), "Oracle should not be set yet");
        assertEq(address(backupAggregator), address(0), "Backup oracle should not be set yet");
        assertEq(heartbeat, 0, "Heartbeat should not be set yet");
        assertEq(backupHeartbeat, 0, "Backup heartbeat should not be set yet");
        assertEq(maxPrice, 0, "Max price should not be set yet");

        (IOracle.Oracle memory pendingOracle, uint64 validAt) = oracleAggregator.pendingOracles(ASSET);
        assertEq(address(pendingOracle.aggregator), address(primaryFeed));
        assertEq(address(pendingOracle.backupAggregator), address(backupFeed));
        assertEq(pendingOracle.heartbeat, HEARTBEAT);
        assertEq(pendingOracle.backupHeartbeat, BACKUP_HEARTBEAT);
        assertEq(pendingOracle.maxPrice, MAX_PRICE);
        assertEq(validAt, block.timestamp + TIMELOCK);
    }

    function test_AcceptPendingOracle() public {
        // Submit pending oracle
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);

        // Warp time past timelock
        vm.warp(block.timestamp + TIMELOCK + 1);

        oracleAggregator.acceptPendingOracle(ASSET);

        // Access the Oracle struct directly from the mapping
        (
            AggregatorV3Interface aggregator,
            AggregatorV3Interface backupAggregator,
            int256 maxPrice,
            uint32 heartbeat,
            uint32 backupHeartbeat
        ) = oracleAggregator.oracles(ASSET);
        assertEq(address(aggregator), address(primaryFeed));
        assertEq(address(backupAggregator), address(backupFeed));
        assertEq(heartbeat, HEARTBEAT);
        assertEq(backupHeartbeat, BACKUP_HEARTBEAT);
        assertEq(maxPrice, MAX_PRICE);

        // Verify pending oracle is cleared
        (IOracle.Oracle memory pendingOracle, uint64 validAt) = oracleAggregator.pendingOracles(ASSET);
        assertEq(address(pendingOracle.aggregator), address(0));
        assertEq(address(pendingOracle.backupAggregator), address(0));
        assertEq(pendingOracle.heartbeat, 0);
        assertEq(pendingOracle.backupHeartbeat, 0);
        assertEq(pendingOracle.maxPrice, 0);
        assertEq(validAt, 0);
    }

    function test_GetPrice_PrimaryOracle() public {
        // Setup oracle
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

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
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

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
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

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
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

        vm.prank(address(0x3));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0x3)));
        oracleAggregator.submitPendingOracle(ASSET, oracle);
    }

    function test_RevertAcceptPendingOracle_BeforeTimelock() public {
        // Submit pending oracle
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

        vm.prank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.expectRevert(abi.encodeWithSignature("TimelockNotElapsed()"));
        // Try to accept before timelock expires
        oracleAggregator.acceptPendingOracle(ASSET);
    }

    function test_RemoveOracle() public {
        // First add an oracle
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

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
                heartbeat: 0,
                backupHeartbeat: 0,
                maxPrice: 0
            })
        );

        // Verify oracle is removed
        (
            AggregatorV3Interface aggregator,
            AggregatorV3Interface backupAggregator,
            int256 maxPrice,
            uint32 heartbeat,
            uint32 backupHeartbeat
        ) = oracleAggregator.oracles(ASSET);
        assertEq(address(aggregator), address(0));
        assertEq(address(backupAggregator), address(0));
        assertEq(heartbeat, 0);
        assertEq(backupHeartbeat, 0);
        assertEq(maxPrice, 0);
    }

    function test_GetPrice_PrimaryExceedsMaxPrice_NoBackup() public {
        // Create an oracle with maxPrice and no backup
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: AggregatorV3Interface(address(0)),
            heartbeat: HEARTBEAT,
            backupHeartbeat: 0,
            maxPrice: MAX_PRICE
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Set primary price above maxPrice
        int256 highPrice = MAX_PRICE + 1000e8;
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: highPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        vm.prank(OWNER);
        primaryFeed.updateRoundData(roundData);

        // Get price - should return maxPrice instead of actual price
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(MAX_PRICE));
        assertEq(decimals, DECIMALS);
    }

    function test_GetPrice_PrimaryExceedsMaxPrice_WithBackup() public {
        // Create an oracle with maxPrice
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Set primary price above maxPrice
        int256 highPrice = MAX_PRICE + 1000e8;
        MockPriceFeed.RoundData memory primaryRoundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: highPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        
        // Set backup price below maxPrice
        int256 validBackupPrice = MAX_PRICE - 1000e8;
        MockPriceFeed.RoundData memory backupRoundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: validBackupPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        
        vm.startPrank(OWNER);
        primaryFeed.updateRoundData(primaryRoundData);
        backupFeed.updateRoundData(backupRoundData);
        vm.stopPrank();

        // Get price - should fallback to backup oracle
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(validBackupPrice));
        assertEq(decimals, DECIMALS);
    }

    function test_GetPrice_BothExceedMaxPrice() public {
        // Create an oracle with maxPrice
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: MAX_PRICE
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Set both primary and backup prices above maxPrice
        int256 highPrimaryPrice = MAX_PRICE + 1000e8;
        MockPriceFeed.RoundData memory primaryRoundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: highPrimaryPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        
        int256 highBackupPrice = MAX_PRICE + 500e8;
        MockPriceFeed.RoundData memory backupRoundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: highBackupPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        
        vm.startPrank(OWNER);
        primaryFeed.updateRoundData(primaryRoundData);
        backupFeed.updateRoundData(backupRoundData);
        vm.stopPrank();

        // Get price - should use backup capped at maxPrice
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(MAX_PRICE));
        assertEq(decimals, DECIMALS);
    }

    function test_GetPrice_WithMaxPriceZero_PrimaryOracle() public {
        // Create an oracle with maxPrice set to 0 (no price cap)
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: 0 // No price cap
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Set very high price that would normally exceed any reasonable cap
        int256 extremelyHighPrice = 1000000e8; // 1 million units
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: extremelyHighPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        vm.prank(OWNER);
        primaryFeed.updateRoundData(roundData);

        // Get price - should return the full price without capping
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(extremelyHighPrice));
        assertEq(decimals, DECIMALS);
    }

    function test_GetPrice_WithMaxPriceZero_FallbackToBackup() public {
        // Create an oracle with maxPrice set to 0 (no price cap)
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: backupFeed,
            heartbeat: HEARTBEAT,
            backupHeartbeat: BACKUP_HEARTBEAT,
            maxPrice: 0 // No price cap
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Make primary oracle stale
        vm.warp(block.timestamp + HEARTBEAT + 1);

        // Set very high price on backup oracle
        int256 extremelyHighBackupPrice = 2000000e8; // 2 million units
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: extremelyHighBackupPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        vm.prank(OWNER);
        backupFeed.updateRoundData(roundData);

        // Get price - should return the full backup price without capping
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(extremelyHighBackupPrice));
        assertEq(decimals, DECIMALS);
    }

    function test_GetPrice_NoBackupAggregator() public {
        // Create an oracle with no backup aggregator
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: AggregatorV3Interface(address(0)),
            heartbeat: HEARTBEAT,
            backupHeartbeat: 0,
            maxPrice: MAX_PRICE
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Set normal price
        int256 newPrice = 3200e8;
        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 2,
            answer: newPrice,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 2
        });
        vm.prank(OWNER);
        primaryFeed.updateRoundData(roundData);

        // Get price - should return the primary price
        (uint256 price, uint8 decimals) = oracleAggregator.getPrice(ASSET);
        assertEq(price, uint256(newPrice));
        assertEq(decimals, DECIMALS);
    }

    function test_RevertGetPrice_NoBackupAggregator_PrimaryStale() public {
        // Create an oracle with no backup aggregator
        IOracle.Oracle memory oracle = IOracle.Oracle({
            aggregator: primaryFeed,
            backupAggregator: AggregatorV3Interface(address(0)),
            heartbeat: HEARTBEAT,
            backupHeartbeat: 0,
            maxPrice: MAX_PRICE
        });

        vm.startPrank(OWNER);
        oracleAggregator.submitPendingOracle(ASSET, oracle);
        vm.warp(block.timestamp + TIMELOCK + 1);
        vm.stopPrank();

        oracleAggregator.acceptPendingOracle(ASSET);

        // Make primary oracle stale
        vm.warp(block.timestamp + HEARTBEAT + 1);

        // Should revert since primary is stale and no backup exists
        vm.expectRevert(abi.encodeWithSignature("OracleIsNotWorking(address)", ASSET));
        oracleAggregator.getPrice(ASSET);
    }
}
