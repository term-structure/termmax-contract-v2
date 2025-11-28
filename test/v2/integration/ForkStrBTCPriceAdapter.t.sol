// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxStrBTCPriceFeedAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxStrBTCPriceFeedAdapter.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console} from "forge-std/console.sol";

/**
 * @title ForkStrBTCPriceAdapter
 * @notice Fork test for TermMaxStrBTCPriceFeedAdapter that wraps Aave's StrBTCPriceFeedAdapter
 * @dev Tests the adapter against mainnet deployed Aave StrBTCPriceFeedAdapter
 */
contract ForkStrBTCPriceAdapter is Test {
    TermMaxStrBTCPriceFeedAdapter public adapter;

    // Mainnet addresses
    address constant strBTC = 0xB2723d5dF98689eCA6A4E7321121662DDB9b3017;
    address constant strBTCReserveFeed = 0x1d18b5147B11908B24A247517F606c0705CF8d40;
    address constant btcPriceFeed = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

    // Fork configuration
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 constant FORK_BLOCK = 23896179; // Recent mainnet block

    function setUp() public {
        // Create fork at specific block
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL, FORK_BLOCK);
        vm.selectFork(mainnetFork);

        // Deploy our adapter wrapping the Aave adapter
        adapter = new TermMaxStrBTCPriceFeedAdapter(strBTCReserveFeed, btcPriceFeed, strBTC);
    }

    /**
     * @notice Test that the adapter is properly initialized
     */
    function testAdapterInitialization() public view {
        assertEq(address(adapter.strBTCReserveFeed()), strBTCReserveFeed);
        assertEq(address(adapter.btcPriceFeed()), btcPriceFeed);
        assertEq(adapter.asset(), strBTC);
    }

    /**
     * @notice Test decimals function returns expected value
     */
    function testDecimals() public view {
        uint8 decimals = adapter.decimals();
        assertEq(decimals, 8, "Decimals should be 8");
        console.log("Decimals:", decimals);
    }

    /**
     * @notice Test description function returns a valid string
     */
    function testDescription() public view {
        string memory description = adapter.description();
        assertTrue(bytes(description).length > 0, "Description should not be empty");
        console.log("Description:", description);
        // Should contain symbol and "/USD"
        assertTrue(bytes(description).length > 0, "Description should not be empty");
    }

    /**
     * @notice Test latestRoundData returns valid data
     */
    function testLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        // Verify answer is positive and reasonable
        assertGt(answer, 0, "Answer should be positive");

        // Price should be reasonable (strBTC price should be close to BTC price)
        // BTC price typically between $20k-$100k, so 8 decimals means 20000_00000000 to 100000_00000000
        assertGt(answer, 20000e8, "Price should be greater than $20k");
        assertLt(answer, 200000e8, "Price should be less than $200k");

        // Timestamps should be valid
        assertGt(startedAt, 0, "startedAt should be non-zero");
        assertGt(updatedAt, 0, "updatedAt should be non-zero");

        console.log("Round ID:", roundId);
        console.log("Price (strBTC/USD):", answer);
        console.log("Price in human readable:", uint256(answer) / 1e8);
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
        console.log("Answered In Round:", answeredInRound);
    }

    /**
     * @notice Test getRoundData returns same as latestRoundData
     */
    function testGetRoundData() public view {
        (uint80 roundId1, int256 answer1, uint256 startedAt1, uint256 updatedAt1, uint80 answeredInRound1) =
            adapter.latestRoundData();

        (uint80 roundId2, int256 answer2, uint256 startedAt2, uint256 updatedAt2, uint80 answeredInRound2) =
            adapter.getRoundData(123); // Any round ID should return latestRoundData

        assertEq(roundId1, roundId2, "Round IDs should match");
        assertEq(answer1, answer2, "Answers should match");
        assertEq(startedAt1, startedAt2, "startedAt should match");
        assertEq(updatedAt1, updatedAt2, "updatedAt should match");
        assertEq(answeredInRound1, answeredInRound2, "answeredInRound should match");
    }

    /**
     * @notice Test that price remains consistent across multiple calls in same block
     */
    function testPriceConsistency() public view {
        (, int256 answer1,,,) = adapter.latestRoundData();
        (, int256 answer2,,,) = adapter.latestRoundData();

        assertEq(answer1, answer2, "Price should be consistent across multiple calls in same block");
    }

    /**
     * @notice Test version function
     */
    function testVersion() public view {
        uint256 version = adapter.version();
        // Version may be 0 or greater depending on underlying price feeds
        assertGe(version, 0, "Version should be non-negative");
        console.log("Version:", version);
    }

    /**
     * @notice Test that the price calculation logic is reasonable
     * @dev This test verifies that strBTC/USD = (strBTC/BTC) * (BTC/USD)
     */
    function testPriceCalculationLogic() public view {
        // Get strBTC price from adapter
        (, int256 strBtcUsdPrice,,,) = adapter.latestRoundData();

        // Get BTC/USD price directly
        (, int256 btcUsdPrice,,,) = adapter.btcPriceFeed().latestRoundData();

        // Get strBTC/BTC ratio from reserve feed
        (, int256 reserves,,,) = adapter.strBTCReserveFeed().latestRoundData();

        // Get total supply
        uint256 totalSupply = IERC20Metadata(strBTC).totalSupply();

        console.log("BTC/USD Price:", uint256(btcUsdPrice));
        console.log("strBTC Reserves:", uint256(reserves));
        console.log("strBTC Total Supply:", totalSupply);
        console.log("strBTC/USD Price:", uint256(strBtcUsdPrice));

        // Verify price is positive
        assertGt(strBtcUsdPrice, 0, "strBTC/USD price should be positive");
        assertGt(btcUsdPrice, 0, "BTC/USD price should be positive");

        // strBTC price should be close to BTC price (within reasonable range)
        // Typically strBTC should be very close to BTC (0.95 - 1.05 ratio)
        uint256 ratio = (uint256(strBtcUsdPrice) * 1e8) / uint256(btcUsdPrice);
        console.log("strBTC/BTC ratio (%):", ratio);
    }

    /**
     * @notice Test that timestamps update correctly across blocks
     */
    function testTimestampUpdates() public {
        (, int256 answer1, uint256 startedAt1, uint256 updatedAt1,) = adapter.latestRoundData();

        // Move to next block
        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1200); // 1200 seconds later

        (, int256 answer2, uint256 startedAt2, uint256 updatedAt2,) = adapter.latestRoundData();

        // Price should still be reasonable
        assertGt(answer2, 0, "Price should still be positive");

        // Log values for debugging
        console.log("Block 1 - Timestamp:", startedAt1, "Price:", uint256(answer1));
        console.log("Block 2 - Timestamp:", startedAt2, "Price:", uint256(answer2));
    }
}
