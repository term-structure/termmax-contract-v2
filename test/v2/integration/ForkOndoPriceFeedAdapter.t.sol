// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxOndoPriceFeedAdapter} from "contracts/v2/oracle/adapters/ondo/TermMaxOndoPriceFeedAdapter.sol";
import {TermMaxOndoPriceFeedAdapterFactory} from
    "contracts/v2/oracle/adapters/ondo/TermMaxOndoPriceFeedAdapterFactory.sol";
import {ISyntheticSharesOracle} from "contracts/v2/extensions/ondo/ISyntheticSharesOracle.sol";
import {TermMaxPriceFeedFactoryV2} from "contracts/v2/factory/TermMaxPriceFeedFactoryV2.sol";
import {ITermMaxPriceFeed} from "contracts/v2/oracle/priceFeeds/ITermMaxPriceFeed.sol";
import {console} from "forge-std/console.sol";

/**
 * @notice Extended interface for testing that includes getSValue
 */
interface ISyntheticSharesOracleExtended is ISyntheticSharesOracle {
    function getSValue(address asset) external view returns (uint128 sValue, bool paused);
}

/**
 * @title ForkOndoPriceFeedAdapterTest
 * @notice Fork test for TermMaxOndoPriceFeedAdapter that wraps Ondo's SyntheticSharesOracle
 * @dev Tests the adapter against mainnet deployed Ondo oracle with TSLAON and NVDAON assets
 */
contract ForkOndoPriceFeedAdapterTest is Test {
    TermMaxOndoPriceFeedAdapterFactory public factory;
    TermMaxOndoPriceFeedAdapter public tslaonAdapter;
    TermMaxOndoPriceFeedAdapter public nvdaonAdapter;
    ISyntheticSharesOracle public ondoOracle;
    ISyntheticSharesOracleExtended public ondoOracleExtended;
    TermMaxPriceFeedFactoryV2 public priceFeedFactory;
    ITermMaxPriceFeed public tslaonUSDConverter;

    // Mainnet addresses
    address constant ONDO_ORACLE = 0xF4Fd8a1B412633e10527454137A29Db7Aa35F15e;
    address constant TSLAON = 0x2494b603319d4D9F9715c9f4496d9E0364B59d93;
    address constant NVDAON = 0xA9eE28C80f960B889dFbd1902055218cBa016F75;
    address constant TSLA_USD_PRICE_FEED = 0xEEA2ae9c074E87596A85ABE698B2Afebc9B57893;
    uint256 constant DEFAULT_MAX_UPDATE_INTERVAL = 0;

    // Fork configuration
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Create fork
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        // Deploy price feed factory first
        priceFeedFactory = new TermMaxPriceFeedFactoryV2();

        // Deploy Ondo adapter factory with price feed factory
        factory = new TermMaxOndoPriceFeedAdapterFactory(ONDO_ORACLE, address(priceFeedFactory));
        ondoOracle = ISyntheticSharesOracle(ONDO_ORACLE);
        ondoOracleExtended = ISyntheticSharesOracleExtended(ONDO_ORACLE);

        // Deploy adapters for TSLAON and NVDAON
        address tslaonAdapterAddr = factory.deployAdapter(TSLAON, DEFAULT_MAX_UPDATE_INTERVAL);
        address nvdaonAdapterAddr = factory.deployAdapter(NVDAON, DEFAULT_MAX_UPDATE_INTERVAL);

        tslaonAdapter = TermMaxOndoPriceFeedAdapter(tslaonAdapterAddr);
        nvdaonAdapter = TermMaxOndoPriceFeedAdapter(nvdaonAdapterAddr);

        // Deploy converter for TSLAON/USD using factory's deployConverter method
        address converterAddr = factory.deployConverter(TSLAON, TSLA_USD_PRICE_FEED, DEFAULT_MAX_UPDATE_INTERVAL);
        tslaonUSDConverter = ITermMaxPriceFeed(converterAddr);
    }

    /**
     * @notice Test factory initialization
     */
    function testFactoryInitialization() public view {
        assertEq(factory.ondoOracle(), ONDO_ORACLE, "Factory oracle address should match");
        assertEq(
            address(factory.priceFeedFactory()), address(priceFeedFactory), "Factory price feed factory should match"
        );
    }

    /**
     * @notice Test factory deployment tracking
     */
    function testFactoryDeploymentTracking() public view {
        assertEq(
            factory.getAdapter(TSLAON, DEFAULT_MAX_UPDATE_INTERVAL),
            address(tslaonAdapter),
            "TSLAON adapter should be tracked"
        );
        assertEq(
            factory.getAdapter(NVDAON, DEFAULT_MAX_UPDATE_INTERVAL),
            address(nvdaonAdapter),
            "NVDAON adapter should be tracked"
        );
    }

    /**
     * @notice Test factory prevents duplicate deployment
     */
    function testFactoryPreventsDuplicateDeployment() public {
        vm.expectRevert(TermMaxOndoPriceFeedAdapterFactory.AdapterAlreadyExists.selector);
        factory.deployAdapter(TSLAON, DEFAULT_MAX_UPDATE_INTERVAL);
    }

    /**
     * @notice Test factory allows redeploying converter (overwrite)
     */
    function testFactoryAllowsConverterRedeploy() public {
        address oldConverter = factory.deployConverter(TSLAON, TSLA_USD_PRICE_FEED, DEFAULT_MAX_UPDATE_INTERVAL);

        // Redeploy converter (e.g., when underlying TSLA/USD price feed changes)
        address newConverter = factory.deployConverter(TSLAON, TSLA_USD_PRICE_FEED, DEFAULT_MAX_UPDATE_INTERVAL);

        assertTrue(newConverter != address(0), "New converter should be deployed");
        assertTrue(newConverter != oldConverter, "Converter should be overwritten with new address");
    }

    /**
     * @notice Test TSLAON adapter initialization
     */
    function testTSLAONAdapterInitialization() public view {
        assertEq(address(tslaonAdapter.ondoOracle()), ONDO_ORACLE, "TSLAON adapter oracle address should match");
        assertEq(tslaonAdapter.asset(), TSLAON, "TSLAON adapter asset address should match");
    }

    /**
     * @notice Test NVDAON adapter initialization
     */
    function testNVDAONAdapterInitialization() public view {
        assertEq(address(nvdaonAdapter.ondoOracle()), ONDO_ORACLE, "NVDAON adapter oracle address should match");
        assertEq(nvdaonAdapter.asset(), NVDAON, "NVDAON adapter asset address should match");
    }

    /**
     * @notice Test adapter maxUpdateInterval initialization
     */
    function testAdapterMaxUpdateIntervalInitialization() public view {
        assertEq(
            tslaonAdapter.maxUpdateInterval(),
            DEFAULT_MAX_UPDATE_INTERVAL,
            "TSLAON adapter maxUpdateInterval should match"
        );
        assertEq(
            nvdaonAdapter.maxUpdateInterval(),
            DEFAULT_MAX_UPDATE_INTERVAL,
            "NVDAON adapter maxUpdateInterval should match"
        );
    }

    /**
     * @notice Test adapter reverts when last update exceeds maxUpdateInterval
     */
    function testTSLAONRevertIfLastUpdateTooOld() public {
        uint256 strictMaxUpdateInterval = 1;
        address strictAdapterAddr = factory.deployAdapter(TSLAON, strictMaxUpdateInterval);
        TermMaxOndoPriceFeedAdapter strictAdapter = TermMaxOndoPriceFeedAdapter(strictAdapterAddr);

        (,, uint256 lastUpdate,,,) = ondoOracle.assetData(TSLAON);

        // Ensure we are beyond the strict interval even if fork timestamp equals lastUpdate.
        if (block.timestamp <= lastUpdate + strictMaxUpdateInterval) {
            vm.warp(lastUpdate + strictMaxUpdateInterval + 1);
        }

        vm.expectRevert(TermMaxOndoPriceFeedAdapter.LastUpdateTooOld.selector);
        strictAdapter.latestRoundData();
    }

    /**
     * @notice Test TSLAON decimals function
     */
    function testTSLAONDecimals() public view {
        uint8 decimals = tslaonAdapter.decimals();
        assertEq(decimals, 18, "Decimals should be 18 (sValue decimals)");
        console.log("TSLAON Decimals:", decimals);
    }

    /**
     * @notice Test NVDAON decimals function
     */
    function testNVDAONDecimals() public view {
        uint8 decimals = nvdaonAdapter.decimals();
        assertEq(decimals, 18, "Decimals should be 18 (sValue decimals)");
        console.log("NVDAON Decimals:", decimals);
    }

    /**
     * @notice Test TSLAON description function
     */
    function testTSLAONDescription() public view {
        string memory description = tslaonAdapter.description();
        assertTrue(bytes(description).length > 0, "Description should not be empty");
        console.log("TSLAON Description:", description);
    }

    /**
     * @notice Test NVDAON description function
     */
    function testNVDAONDescription() public view {
        string memory description = nvdaonAdapter.description();
        assertTrue(bytes(description).length > 0, "Description should not be empty");
        console.log("NVDAON Description:", description);
    }

    /**
     * @notice Test TSLAON version function
     */
    function testTSLAONVersion() public view {
        uint256 version = tslaonAdapter.version();
        assertEq(version, 1, "Version should be 1");
    }

    /**
     * @notice Test TSLAON latestRoundData returns valid data
     */
    function testTSLAONLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            tslaonAdapter.latestRoundData();

        // Verify answer is positive and reasonable (sValue should be > 0)
        assertGt(answer, 0, "sValue should be positive");

        // Verify timestamps are reasonable (should be from past updates)
        assertGt(startedAt, 0, "startedAt should be greater than 0");
        assertGt(updatedAt, 0, "updatedAt should be greater than 0");
        assertEq(startedAt, updatedAt, "startedAt and updatedAt should match");

        // roundId and answeredInRound should be 1
        assertEq(roundId, 1, "roundId should be 1");
        assertEq(answeredInRound, 1, "answeredInRound should be 1");

        console.log("TSLAON sValue:", uint256(answer));
        console.log("TSLAON sValue (human readable):", uint256(answer) / 1e18);
        console.log("TSLAON Last Update:", updatedAt);
    }

    /**
     * @notice Test NVDAON latestRoundData returns valid data
     */
    function testNVDAONLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            nvdaonAdapter.latestRoundData();

        // Verify answer is positive and reasonable (sValue should be > 0)
        assertGt(answer, 0, "sValue should be positive");

        // Verify timestamps are reasonable
        assertGt(startedAt, 0, "startedAt should be greater than 0");
        assertGt(updatedAt, 0, "updatedAt should be greater than 0");
        assertEq(startedAt, updatedAt, "startedAt and updatedAt should match");

        // roundId and answeredInRound should be 1
        assertEq(roundId, 1, "roundId should be 1");
        assertEq(answeredInRound, 1, "answeredInRound should be 1");

        console.log("NVDAON sValue:", uint256(answer));
        console.log("NVDAON sValue (human readable):", uint256(answer) / 1e18);
        console.log("NVDAON Last Update:", updatedAt);
    }

    /**
     * @notice Test that sValue remains consistent across multiple calls
     */
    function testTSLAONPriceConsistency() public view {
        (, int256 answer1,,,) = tslaonAdapter.latestRoundData();
        (, int256 answer2,,,) = tslaonAdapter.latestRoundData();

        assertEq(answer1, answer2, "sValue should be consistent across multiple calls in same block");
    }

    /**
     * @notice Test that the adapter correctly reads from Ondo oracle
     */
    function testTSLAONAdapterMatchesOracle() public view {
        (uint128 oracleSValue, bool paused) = ondoOracleExtended.getSValue(TSLAON);
        (, int256 adapterAnswer,,,) = tslaonAdapter.latestRoundData();

        assertFalse(paused, "Oracle should not be paused");
        assertEq(int256(uint256(oracleSValue)), adapterAnswer, "Adapter answer should match oracle sValue");
    }

    /**
     * @notice Test that the adapter correctly reads from Ondo oracle for NVDAON
     */
    function testNVDAONAdapterMatchesOracle() public view {
        (uint128 oracleSValue, bool paused) = ondoOracleExtended.getSValue(NVDAON);
        (, int256 adapterAnswer,,,) = nvdaonAdapter.latestRoundData();

        assertFalse(paused, "Oracle should not be paused");
        assertEq(int256(uint256(oracleSValue)), adapterAnswer, "Adapter answer should match oracle sValue");
    }

    /**
     * @notice Test that adapter uses lastUpdate from oracle
     */
    function testTSLAONTimestampMatchesOracle() public view {
        (,, uint256 startedAt, uint256 updatedAt,) = tslaonAdapter.latestRoundData();

        assertEq(
            startedAt, block.timestamp, "startedAt should match block timestamp since dividends are rarely updated"
        );
        assertEq(
            updatedAt, block.timestamp, "updatedAt should match block timestamp since dividends are rarely updated"
        );
    }

    /**
     * @notice Test that adapter uses lastUpdate from oracle for NVDAON
     */
    function testNVDAONTimestampMatchesOracle() public view {
        (,, uint256 startedAt, uint256 updatedAt,) = nvdaonAdapter.latestRoundData();

        assertEq(
            startedAt, block.timestamp, "startedAt should match block timestamp since dividends are rarely updated"
        );
        assertEq(
            updatedAt, block.timestamp, "updatedAt should match block timestamp since dividends are rarely updated"
        );
    }

    /**
     * @notice Test getRoundData reverts as expected
     */
    function testGetRoundDataReverts() public {
        vm.expectRevert(TermMaxOndoPriceFeedAdapter.GetRoundDataNotSupported.selector);
        tslaonAdapter.getRoundData(1);
    }

    /**
     * @notice Test that adapter correctly detects when oracle is NOT paused
     */
    function testOracleNotPaused() public view {
        (,, uint256 pauseStartTime,,,) = ondoOracle.assetData(TSLAON);

        // If pauseStartTime is 0 or in the future, oracle is not paused
        bool expectedPaused = pauseStartTime > 0 && block.timestamp >= pauseStartTime;

        if (!expectedPaused) {
            // Should not revert
            tslaonAdapter.latestRoundData();
        }
    }

    /**
     * @notice Test reading asset data directly
     */
    function testReadAssetData() public view {
        (
            uint128 sValue,
            uint128 pendingSValue,
            uint256 lastUpdate,
            uint256 pauseStartTime,
            uint16 allowedDriftBps,
            uint48 driftCooldown
        ) = ondoOracle.assetData(TSLAON);

        console.log("TSLAON Asset Data:");
        console.log("  sValue:", sValue);
        console.log("  pendingSValue:", pendingSValue);
        console.log("  lastUpdate:", lastUpdate);
        console.log("  pauseStartTime:", pauseStartTime);
        console.log("  allowedDriftBps:", allowedDriftBps);
        console.log("  driftCooldown:", driftCooldown);

        assertGt(sValue, 0, "sValue should be positive");
        assertGt(lastUpdate, 0, "lastUpdate should be positive");
    }

    /**
     * @notice Test TSLAON/USD converter initialization
     */
    function testTSLAONConverterInitialization() public view {
        assertEq(tslaonUSDConverter.asset(), TSLAON, "Converter asset should be TSLAON");
        assertEq(tslaonUSDConverter.decimals(), 8, "Converter should return 8 decimals");
    }

    /**
     * @notice Test TSLAON/USD converter returns valid price
     */
    function testTSLAONConverterPrice() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            tslaonUSDConverter.latestRoundData();

        // Verify answer is positive
        assertGt(answer, 0, "TSLAON/USD price should be positive");

        (,, uint256 tslaUpdatedAt, uint256 tslaUpdatedAt2,) = ITermMaxPriceFeed(TSLA_USD_PRICE_FEED).latestRoundData();

        // Verify timestamps are reasonable
        assertEq(
            startedAt,
            tslaUpdatedAt,
            "startedAt should match original TSLA/USD price feed since dividends are rarely updated"
        );
        assertEq(
            updatedAt,
            tslaUpdatedAt2,
            "updatedAt should match original TSLA/USD price feed since dividends are rarely updated"
        );

        console.log("TSLAON/USD Price:", uint256(answer));
        console.log("TSLAON/USD Price (human readable, 8 decimals):", uint256(answer) / 1e8);
    }

    /**
     * @notice Test TSLAON/USD converter price calculation
     * @dev Verifies that converter price = sValue × TSLA/USD price
     */
    function testTSLAONConverterPriceCalculation() public view {
        // Get sValue from adapter
        (, int256 sValue,,,) = tslaonAdapter.latestRoundData();

        // Get TSLA/USD price
        (, int256 tslaPrice,,,) = ITermMaxPriceFeed(TSLA_USD_PRICE_FEED).latestRoundData();

        // Get converter price
        (, int256 converterPrice,,,) = tslaonUSDConverter.latestRoundData();

        // Calculate expected price: sValue (18 decimals) × TSLA price (8 decimals) / 1e18 = result (8 decimals)
        int256 expectedPrice = int256((uint256(sValue) * uint256(tslaPrice)) / 1e18);

        console.log("sValue:", uint256(sValue));
        console.log("TSLA/USD Price:", uint256(tslaPrice));
        console.log("Expected TSLAON/USD:", uint256(expectedPrice));
        console.log("Actual TSLAON/USD:", uint256(converterPrice));

        // Allow small rounding difference
        assertApproxEqRel(
            uint256(converterPrice), uint256(expectedPrice), 0.01e18, "Converter price should match calculated price"
        );
    }

    /**
     * @notice Test TSLAON/USD converter description
     */
    function testTSLAONConverterDescription() public view {
        string memory description = tslaonUSDConverter.description();
        assertTrue(bytes(description).length > 0, "Description should not be empty");
        console.log("TSLAON/USD Converter Description:", description);
    }
}
