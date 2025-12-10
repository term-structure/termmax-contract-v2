// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxDUSDPriceFeedAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxDUSDPriceFeedAdapter.sol";
import {console} from "forge-std/console.sol";

interface IDUSDOracle {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function getSharePrice() external view returns (uint256);
}

/**
 * @title ForkDUSDPriceFeedAdapterTest
 * @notice Fork test for TermMaxDUSDPriceFeedAdapter that wraps DUSD Oracle
 * @dev Tests the adapter against mainnet deployed DUSD Oracle
 */
contract ForkDUSDPriceFeedAdapterTest is Test {
    TermMaxDUSDPriceFeedAdapter public dusdAdapter;
    IDUSDOracle public dusdOracle;

    // Mainnet addresses
    address constant DUSD_ORACLE = 0xFFCBc7A7eEF2796C277095C66067aC749f4cA078;
    address constant DUSD_ASSET = 0x1e33E98aF620F1D563fcD3cfd3C75acE841204ef;

    // Fork configuration
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    uint256 constant FORK_BLOCK = 23980501;

    function setUp() public {
        // Create fork at specific block
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL, FORK_BLOCK);
        vm.selectFork(mainnetFork);

        // Deploy our adapter wrapping the DUSD oracle
        dusdAdapter = new TermMaxDUSDPriceFeedAdapter(DUSD_ORACLE, DUSD_ASSET);
        dusdOracle = IDUSDOracle(DUSD_ORACLE);
    }

    /**
     * @notice Test that the adapter is properly initialized
     */
    function testAdapterInitialization() public view {
        assertEq(address(dusdAdapter.dusdOracle()), DUSD_ORACLE, "DUSD oracle address should match");
        assertEq(dusdAdapter.asset(), DUSD_ASSET, "DUSD asset address should match");
    }

    /**
     * @notice Test decimals function returns expected value
     */
    function testDecimals() public view {
        uint8 decimals = dusdAdapter.decimals();
        uint8 oracleDecimals = dusdOracle.decimals();

        assertEq(decimals, oracleDecimals, "Decimals should match DUSD oracle");
        console.log("Decimals:", decimals);
    }

    /**
     * @notice Test description function returns a valid string
     */
    function testDescription() public view {
        string memory description = dusdAdapter.description();
        string memory oracleDescription = dusdOracle.description();

        assertTrue(bytes(description).length > 0, "Description should not be empty");
        assertEq(description, oracleDescription, "Description should match DUSD oracle");
        console.log("Description:", description);
    }

    /**
     * @notice Test version function
     */
    function testVersion() public view {
        uint256 version = dusdAdapter.version();
        assertEq(version, 1, "Version should be 1");
    }

    /**
     * @notice Test asset function returns correct address
     */
    function testAsset() public view {
        address asset = dusdAdapter.asset();
        assertEq(asset, DUSD_ASSET, "Asset should be DUSD");
    }

    /**
     * @notice Test latestRoundData returns valid data
     */
    function testLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            dusdAdapter.latestRoundData();

        // Verify answer is positive and reasonable
        assertGt(answer, 1, "Answer should be positive");

        // Timestamps should match block.timestamp (as per implementation)
        assertEq(startedAt, block.timestamp, "startedAt should be block.timestamp");
        assertEq(updatedAt, block.timestamp, "updatedAt should be block.timestamp");

        // roundId and answeredInRound are not set in the implementation (default to 1)
        assertEq(roundId, 1, "roundId should be 1");
        assertEq(answeredInRound, 1, "answeredInRound should be 1");

        console.log("Price (DUSD/USDC):", answer);
        console.log("Price in human readable (18 decimals):", uint256(answer) / 1e18);
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
    }

    /**
     * @notice Test that price remains consistent across multiple calls
     */
    function testPriceConsistency() public view {
        (, int256 answer1,,,) = dusdAdapter.latestRoundData();
        (, int256 answer2,,,) = dusdAdapter.latestRoundData();

        assertEq(answer1, answer2, "Price should be consistent across multiple calls in same block");
    }

    /**
     * @notice Test that timestamps update correctly across blocks
     */
    function testTimestampUpdates() public {
        (, int256 answer1, uint256 startedAt1, uint256 updatedAt1,) = dusdAdapter.latestRoundData();

        // Move to next block
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12); // 12 second block time

        (, int256 answer2, uint256 startedAt2, uint256 updatedAt2,) = dusdAdapter.latestRoundData();

        // Timestamps should reflect new block timestamp
        assertEq(startedAt2, block.timestamp, "startedAt should update to new block timestamp");
        assertEq(updatedAt2, block.timestamp, "updatedAt should update to new block timestamp");
        assertGt(startedAt2, startedAt1, "New startedAt should be greater than previous");
        assertGt(updatedAt2, updatedAt1, "New updatedAt should be greater than previous");

        // Price should still be reasonable
        assertGt(answer2, 0, "Price should still be positive");

        console.log("Block 1 - Timestamp:", startedAt1, "Price:", uint256(answer1));
        console.log("Block 2 - Timestamp:", startedAt2, "Price:", uint256(answer2));
    }

    /**
     * @notice Test that the adapter correctly wraps the DUSD oracle
     */
    function testAdapterWrapping() public view {
        // Call our adapter
        (, int256 ourAnswer,,,) = dusdAdapter.latestRoundData();
        uint8 ourDecimals = dusdAdapter.decimals();
        string memory ourDescription = dusdAdapter.description();

        // Call DUSD oracle directly
        uint256 sharePrice = dusdOracle.getSharePrice();
        uint8 oracleDecimals = dusdOracle.decimals();
        string memory oracleDescription = dusdOracle.description();

        // Our answer should match oracle's getSharePrice
        assertEq(uint256(ourAnswer), sharePrice, "Our answer should match DUSD oracle's getSharePrice");

        // Verify decimals match
        assertEq(ourDecimals, oracleDecimals, "Decimals should match");

        // Verify description matches
        assertEq(ourDescription, oracleDescription, "Description should match");

        console.log("DUSD oracle getSharePrice:", sharePrice);
        console.log("Our latestRoundData answer:", uint256(ourAnswer));
    }

    /**
     * @notice Test that getRoundData reverts as expected
     */
    function testGetRoundDataReverts() public {
        vm.expectRevert(TermMaxDUSDPriceFeedAdapter.GetRoundDataNotSupported.selector);
        dusdAdapter.getRoundData(1);
    }

    /**
     * @notice Test price is within reasonable bounds
     */
    function testPriceReasonableBounds() public view {
        (, int256 answer,,,) = dusdAdapter.latestRoundData();

        // DUSD/USDC price should be around 1e18 (1.0 with 18 decimals)
        // Allow for some deviation but ensure it's reasonable
        assertGt(uint256(answer), 0.5e18, "Price should be greater than 0.5");
        assertLt(uint256(answer), 2e18, "Price should be less than 2.0");

        console.log("DUSD/USDC Price:", uint256(answer));
        console.log("Price ratio (should be close to 1.0):", uint256(answer) * 100 / 1e18, "/ 100");
    }
}
