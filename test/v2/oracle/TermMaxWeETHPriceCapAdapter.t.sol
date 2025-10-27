// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxWeETHPriceCapAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxWeETHPriceCapAdapter.sol";
import {IPriceCapAdapter} from "contracts/v2/extensions/aave/IPriceCapAdapter.sol";
import {console} from "forge-std/console.sol";

/**
 * @title TermMaxWeETHPriceCapAdapterTest
 * @notice Fork test for TermMaxWeETHPriceCapAdapter that wraps Aave's WeETHPriceCapAdapter
 * @dev Tests the adapter against mainnet deployed Aave WeETHPriceCapAdapter
 */
contract TermMaxWeETHPriceCapAdapterTest is Test {
    TermMaxWeETHPriceCapAdapter public adapter;
    IPriceCapAdapter public aaveWeETHPriceCapAdapter;

    // Mainnet addresses
    address constant AAVE_WEETH_PRICE_CAP_ADAPTER = 0x87625393534d5C102cADB66D37201dF24cc26d4C;

    // Fork configuration
    string MAINNET_RPC_URL = vm.envString("ETH_MAINNET_RPC_URL");
    uint256 constant FORK_BLOCK = 23668976; // Block number used in Aave's test

    function setUp() public {
        // Create fork at specific block
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL, FORK_BLOCK);
        vm.selectFork(mainnetFork);

        // Deploy our adapter wrapping the Aave adapter
        adapter = new TermMaxWeETHPriceCapAdapter(AAVE_WEETH_PRICE_CAP_ADAPTER);
        aaveWeETHPriceCapAdapter = IPriceCapAdapter(AAVE_WEETH_PRICE_CAP_ADAPTER);
    }

    /**
     * @notice Test that the adapter is properly initialized
     */
    function testAdapterInitialization() public view {
        assertEq(address(adapter.adapter()), AAVE_WEETH_PRICE_CAP_ADAPTER);
    }

    /**
     * @notice Test decimals function returns expected value
     */
    function testDecimals() public view {
        uint8 decimals = adapter.decimals();
        // Aave price cap adapters typically use 8 decimals (Chainlink standard)
        assertEq(decimals, aaveWeETHPriceCapAdapter.decimals(), "Decimals should be 8");
        console.log("Decimals:", decimals);
    }

    /**
     * @notice Test description function returns a valid string
     */
    function testDescription() public view {
        string memory description = adapter.description();
        // Should return the Aave adapter's description
        assertTrue(bytes(description).length > 0, "Description should not be empty");
        assertEq(description, aaveWeETHPriceCapAdapter.description(), "Description should be the same as Aave adapter");
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

        // roundId and answeredInRound are not set in the implementation (default to 0)
        assertEq(roundId, 0, "roundId should be 0");
        assertEq(answeredInRound, 0, "answeredInRound should be 0");

        console.log("Price (weETH/USD):", answer);
        console.log("Price in human readable:", uint256(answer) / 1e8);
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
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

        // console.log("Block 1 - Timestamp:", startedAt1, "Price:", answer1);
        // console.log("Block 2 - Timestamp:", startedAt2, "Price:", answer2);
    }

    /**
     * @notice Test that the adapter correctly wraps the Aave adapter
     */
    function testAdapterWrapping() public view {
        // Call our adapter
        (, int256 ourAnswer,,,) = adapter.latestRoundData();
        uint8 ourDecimals = adapter.decimals();
        string memory ourDescription = adapter.description();

        // Call Aave adapter directly
        (bool success, bytes memory data) =
            AAVE_WEETH_PRICE_CAP_ADAPTER.staticcall(abi.encodeWithSignature("latestAnswer()"));
        require(success, "Direct call to Aave adapter failed");
        int256 aaveAnswer = abi.decode(data, (int256));

        // Our answer should match Aave's latestAnswer
        assertEq(ourAnswer, aaveAnswer, "Our answer should match Aave adapter's latestAnswer");

        // Verify decimals match
        (success, data) = AAVE_WEETH_PRICE_CAP_ADAPTER.staticcall(abi.encodeWithSignature("decimals()"));
        require(success, "Failed to get decimals from Aave adapter");
        uint8 aaveDecimals = abi.decode(data, (uint8));
        assertEq(ourDecimals, aaveDecimals, "Decimals should match");

        // Verify description matches
        (success, data) = AAVE_WEETH_PRICE_CAP_ADAPTER.staticcall(abi.encodeWithSignature("description()"));
        require(success, "Failed to get description from Aave adapter");
        string memory aaveDescription = abi.decode(data, (string));
        assertEq(ourDescription, aaveDescription, "Description should match");

        console.log("Aave latestAnswer:", aaveAnswer);
        console.log("Our latestRoundData answer:", ourAnswer);
    }
}
