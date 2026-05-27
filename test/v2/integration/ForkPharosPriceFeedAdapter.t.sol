// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    TermMaxPharosPriceFeedAdapter,
    IPharosOracle
} from "contracts/v2/oracle/adapters/pharos/TermMaxPharosPriceFeedAdapter.sol";
import {TermMaxPharosPriceFeedAdapterFactory} from
    "contracts/v2/oracle/adapters/pharos/TermMaxPharosPriceFeedAdapterFactory.sol";
import {TermMaxPriceFeedFactoryV2} from "contracts/v2/factory/TermMaxPriceFeedFactoryV2.sol";
import {ITermMaxPriceFeed} from "contracts/v2/oracle/priceFeeds/ITermMaxPriceFeed.sol";
import {console} from "forge-std/console.sol";

/**
 * @title ForkPharosPriceFeedAdapter
 * @notice Fork test for TermMaxPharosPriceFeedAdapter that wraps Pharos oracle
 * @dev Tests the adapter against mainnet deployed Pharos oracle with USDC asset
 */
contract ForkPharosPriceFeedAdapter is Test {
    TermMaxPharosPriceFeedAdapterFactory public factory;
    TermMaxPharosPriceFeedAdapter public usdcUSDAdapter;
    IPharosOracle public pharosOracle;
    TermMaxPriceFeedFactoryV2 public priceFeedFactory;

    // Mainnet addresses
    address constant USDC_ORACLE = 0x8d08eA83A55ad1e805b5660F5eC76C99C6aF5eaf;
    address constant USDC = 0xC879C018dB60520F4355C26eD1a6D572cdAC1815;

    // Fork configuration
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Create fork
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        // Deploy price feed factory first
        priceFeedFactory = new TermMaxPriceFeedFactoryV2();

        // Deploy Pharos adapter factory with price feed factory
        factory = new TermMaxPharosPriceFeedAdapterFactory();
        pharosOracle = IPharosOracle(USDC_ORACLE);

        // Deploy adapters for USDC
        address usdcUSDAdapterAddr = factory.deployAdapter(USDC_ORACLE, USDC);
        usdcUSDAdapter = TermMaxPharosPriceFeedAdapter(usdcUSDAdapterAddr);
    }

    function testLastRoundData() public view {
        int256 anwser = pharosOracle.latestAnswer();
        uint256 timestamp = pharosOracle.latestTimestamp();
        console.log("Pharos oracle latest answer:", anwser);
        console.log("Pharos oracle latest timestamp:", timestamp);
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            usdcUSDAdapter.latestRoundData();
        console.log("Adapter latest round ID:", roundId);
        console.log("Adapter latest answer:", answer);
        console.log("Adapter latest startedAt:", startedAt);
        console.log("Adapter latest updatedAt:", updatedAt);
        console.log("Adapter latest answeredInRound:", answeredInRound);
        assertEq(answer, anwser, "Adapter answer should match Pharos oracle answer");
        assertEq(updatedAt, timestamp, "Adapter updatedAt should match Pharos oracle timestamp");
        assertEq(roundId, uint80(timestamp), "Adapter roundId should match Pharos oracle timestamp as uint80");
        assertEq(
            answeredInRound, uint80(timestamp), "Adapter answeredInRound should match Pharos oracle timestamp as uint80"
        );
    }

    function testDecimals() public view {
        uint8 decimals = usdcUSDAdapter.decimals();
        uint8 expectedDecimals = pharosOracle.decimals();
        console.log("Adapter decimals:", decimals);
        console.log("Pharos oracle decimals:", expectedDecimals);
        assertEq(decimals, expectedDecimals, "Adapter decimals should match Pharos oracle decimals");
    }

    function testDescription() public view {
        string memory description = usdcUSDAdapter.description();
        console.log("Adapter description:", description);
    }
}
