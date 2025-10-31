// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    TermMaxSparkLinearOracleAdapter,
    ISparkLinearOracle
} from "contracts/v2/oracle/priceFeeds/TermMaxSparkLinearOracleAdapter.sol";
import {IOracle, OracleAggregator} from "contracts/v1/oracle/OracleAggregator.sol";
import {console} from "forge-std/console.sol";

/**
 * @title TermMaxSparkLinearOracleAdapterTest
 * @notice Fork test for TermMaxSparkLinearOracleAdapter that wraps SparkLinearOracle
 * @dev Tests the adapter against mainnet deployed SparkLinearOracle
 */
contract ForkSparkLinearOracleAdapterTest is Test {
    TermMaxSparkLinearOracleAdapter public adapter;
    ISparkLinearOracle public sparkLinearOracle;

    OracleAggregator public oracleAggregator = OracleAggregator(0xE3a31690392E8E18DC3d862651C079339E2c1ADE);

    // Mainnet addresses
    address constant PENDLE_SPARK_LINEAR_ORACLE = 0xeD2b85Df608fa9FBe95371D01566e12fb005EDeE;

    // Fork configuration
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 constant FORK_BLOCK = 23694295; // Block number used in Pendle's test
    uint256 constant BLOCK_TIMESTAMP = 1761877213;

    function setUp() public {
        // Create fork at specific block
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL, FORK_BLOCK);
        vm.selectFork(mainnetFork);
        vm.warp(BLOCK_TIMESTAMP - 1 days);

        // Deploy our adapter wrapping the Pendle adapter
        adapter = new TermMaxSparkLinearOracleAdapter(PENDLE_SPARK_LINEAR_ORACLE);
        sparkLinearOracle = ISparkLinearOracle(PENDLE_SPARK_LINEAR_ORACLE);
        address asset = adapter.asset();
        vm.prank(oracleAggregator.owner());
        oracleAggregator.submitPendingOracle(
            asset,
            IOracle.Oracle({
                aggregator: ISparkLinearOracle(address(adapter)),
                backupAggregator: ISparkLinearOracle(address(0)),
                heartbeat: 86400
            })
        );
        vm.warp(BLOCK_TIMESTAMP);
        oracleAggregator.acceptPendingOracle(adapter.asset());
    }

    /**
     * @notice Test that the adapter is properly initialized
     */
    function testAdapterInitialization() public view {
        assertEq(address(adapter.adapter()), PENDLE_SPARK_LINEAR_ORACLE);
    }

    /**
     * @notice Test asset function returns the PT address
     */
    function testAsset() public view {
        address asset = adapter.asset();

        // Asset should be a valid address (not zero address)
        assertTrue(asset != address(0), "Asset should not be zero address");

        // Asset should match the PT address from the underlying Spark Linear Oracle
        (bool success, bytes memory data) = PENDLE_SPARK_LINEAR_ORACLE.staticcall(abi.encodeWithSignature("PT()"));
        require(success, "Failed to get PT from Spark Linear Oracle");
        address ptAddress = abi.decode(data, (address));

        assertEq(asset, ptAddress, "Asset should match PT address from underlying oracle");
        console.log("PT Asset Address:", asset);
    }

    /**
     * @notice Test decimals function returns expected value
     */
    function testDecimals() public view {
        uint8 decimals = adapter.decimals();
        // Should match the Spark Linear Oracle decimals
        assertEq(decimals, sparkLinearOracle.decimals(), "Decimals should match underlying oracle");
        console.log("Decimals:", decimals);
    }

    /**
     * @notice Test description function returns a valid string
     */
    function testDescription() public view {
        string memory description = adapter.description();
        // Should return the Spark Linear Oracle's description
        assertTrue(bytes(description).length > 0, "Description should not be empty");
        console.log("Description:", description);
    }

    /**
     * @notice Test latestRoundData returns valid data
     */
    function testLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        // Verify answer is positive and reasonable
        assertGt(answer, 0, "Answer should be positive");

        // Timestamps should match block.timestamp (as per implementation)
        assertEq(startedAt, block.timestamp, "startedAt should be block.timestamp");
        assertEq(updatedAt, block.timestamp, "updatedAt should be block.timestamp");

        console.log("Price:", answer);
        console.log("Price in human readable:", uint256(answer) / (10 ** adapter.decimals()));
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
        console.log("Round ID:", roundId);
        console.log("Answered In Round:", answeredInRound);
    }

    /**
     * @notice Test that price remains consistent across multiple calls
     */
    function testPriceConsistency() public view {
        (, int256 answer1,,,) = adapter.latestRoundData();
        (, int256 answer2,,,) = adapter.latestRoundData();

        assertEq(answer1, answer2, "Price should be consistent across multiple calls in same block");
    }

    /**
     * @notice Test that timestamps update correctly across blocks
     */
    function testTimestampUpdates() public {
        (, int256 answer1, uint256 startedAt1, uint256 updatedAt1,) = adapter.latestRoundData();

        // Move to next block
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12); // 12 second block time

        (, int256 answer2, uint256 startedAt2, uint256 updatedAt2,) = adapter.latestRoundData();

        // Timestamps should reflect new block timestamp
        assertEq(startedAt2, block.timestamp, "startedAt should update to new block timestamp");
        assertEq(updatedAt2, block.timestamp, "updatedAt should update to new block timestamp");
        assertGt(startedAt2, startedAt1, "New startedAt should be greater than previous");
        assertGt(updatedAt2, updatedAt1, "New updatedAt should be greater than previous");

        // Price may change slightly but should still be reasonable
        assertGt(answer2, 0, "Price should still be positive");

        console.log("Block 1 - Timestamp:", startedAt1);
        console.log("Block 1 - Price:", uint256(answer1));
        console.log("Block 2 - Timestamp:", startedAt2);
        console.log("Block 2 - Price:", uint256(answer2));
    }

    /**
     * @notice Test that the adapter correctly wraps the Spark Linear Oracle
     */
    function testAdapterWrapping() public view {
        // Call our adapter
        (, int256 ourAnswer, uint256 ourStartedAt, uint256 ourUpdatedAt,) = adapter.latestRoundData();
        uint8 ourDecimals = adapter.decimals();
        string memory ourDescription = adapter.description();

        // Call Spark Linear Oracle directly
        (
            uint80 sparkRoundId,
            int256 sparkAnswer,
            uint256 sparkStartedAt,
            uint256 sparkUpdatedAt,
            uint80 sparkAnsweredInRound
        ) = sparkLinearOracle.latestRoundData();

        // Our answer should match Spark's answer
        assertEq(ourAnswer, sparkAnswer, "Our answer should match Spark Linear Oracle's answer");

        // Our timestamps should be block.timestamp (not Spark's timestamps)
        assertEq(ourStartedAt, block.timestamp, "Our startedAt should be block.timestamp");
        assertEq(ourUpdatedAt, block.timestamp, "Our updatedAt should be block.timestamp");

        // Verify decimals match
        assertEq(ourDecimals, sparkLinearOracle.decimals(), "Decimals should match");

        console.log("Spark Linear Oracle answer:", uint256(sparkAnswer));
        console.log("Spark Linear Oracle startedAt:", sparkStartedAt);
        console.log("Spark Linear Oracle updatedAt:", sparkUpdatedAt);
        console.log("Our adapter answer:", uint256(ourAnswer));
        console.log("Our adapter startedAt (block.timestamp):", ourStartedAt);
        console.log("Our adapter updatedAt (block.timestamp):", ourUpdatedAt);
    }

    /**
     * @notice Test reading price from OracleAggregator using the adapter
     */
    function testGetPriceFromOracleAggregator() public view {
        address ptAsset = adapter.asset();

        // Try to get the price from the Oracle Aggregator
        // This will revert if the oracle is not configured for this asset
        try oracleAggregator.getPrice(ptAsset) returns (uint256 price, uint8 decimals) {
            // If successful, verify the price is valid
            assertGt(price, 0, "Price from OracleAggregator should be positive");
            assertGt(decimals, 0, "Decimals from OracleAggregator should be positive");

            console.log("Successfully retrieved price from OracleAggregator");
            console.log("PT Asset:", ptAsset);
            console.log("Price from OracleAggregator:", price);
            console.log("Decimals from OracleAggregator:", decimals);
            console.log("Human readable price:", price / (10 ** decimals));

            // Compare with adapter's price
            (, int256 adapterAnswer,,,) = adapter.latestRoundData();
            uint8 adapterDecimals = adapter.decimals();

            console.log("Price from Adapter:", uint256(adapterAnswer));
            console.log("Decimals from Adapter:", adapterDecimals);

            // Note: They might have different decimals, so we need to normalize for comparison
            // If they have the same decimals, they should return the same price
            if (decimals == adapterDecimals) {
                assertEq(price, uint256(adapterAnswer), "Prices should match when decimals are the same");
            }
        } catch {
            // If the oracle is not configured for this asset, log a message
            console.log("Oracle not configured for PT asset in OracleAggregator:", ptAsset);
            revert("This is not expected if the adapter hasn't been registered yet");
        }
    }
}
