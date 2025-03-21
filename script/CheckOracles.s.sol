// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract CheckOracles is Script {
    // Network-specific config
    string network;
    address oracleAggregatorAddr;
    JsonLoader.Config[] configs;
    mapping(address => bool) tokenChecked;

    // Struct to store detailed diagnostics about tokens with issues
    struct TokenDiagnostics {
        address tokenAddr;
        address priceFeedAddr;
        string symbol;
        string errorType; // "NO_ORACLE", "PRICE_FEED_ERROR", "ORACLE_ERROR", "STALE_DATA"
        string errorMessage;
        bool aggregatorWorks; // Whether the direct price feed works
        bool oracleWorks; // Whether the Oracle.getPrice works
        uint256 lastUpdateTime;
        int256 rawAnswer; // Raw answer from price feed
        uint8 priceFeedDecimals; // Decimals of the price feed
        uint8 tokenDecimals; // Decimals of the token
    }

    TokenDiagnostics[] public diagnostics;

    function setUp() public {
        // Default to eth-mainnet or use environment variable if available
        network = vm.envOr("NETWORK", string("eth-mainnet"));

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        string memory json = vm.readFile(deploymentPath);

        oracleAggregatorAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
    }

    function run() public {
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, ".json");
        string memory deployData = vm.readFile(deployDataPath);
        configs = JsonLoader.getConfigsFromJson(deployData);

        console.log("=== Checking Oracle Prices for %s ===", network);
        console.log("Oracle Aggregator: %s", oracleAggregatorAddr);
        console.log("Number of configs: %d", configs.length);
        console.log("");

        IOracle oracle = IOracle(oracleAggregatorAddr);
        OracleAggregator oracleAggregator = OracleAggregator(oracleAggregatorAddr);

        // Track tokens with price issues
        uint256 successCount = 0;
        address[] memory tokensWithIssues = new address[](configs.length * 2); // Max possible issues
        uint256 issueCount = 0;

        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            // Check underlying token
            if (!tokenChecked[config.underlyingConfig.tokenAddr]) {
                bool success = checkTokenOracle(
                    oracle,
                    oracleAggregator,
                    config.underlyingConfig.tokenAddr,
                    config.underlyingConfig.priceFeedAddr,
                    uint32(config.underlyingConfig.heartBeat),
                    "Underlying"
                );

                if (success) {
                    successCount++;
                } else {
                    tokensWithIssues[issueCount] = config.underlyingConfig.tokenAddr;
                    issueCount++;
                }

                tokenChecked[config.underlyingConfig.tokenAddr] = true;
            }

            // Check collateral token
            if (!tokenChecked[config.collateralConfig.tokenAddr]) {
                bool success = checkTokenOracle(
                    oracle,
                    oracleAggregator,
                    config.collateralConfig.tokenAddr,
                    config.collateralConfig.priceFeedAddr,
                    uint32(config.collateralConfig.heartBeat),
                    "Collateral"
                );

                if (success) {
                    successCount++;
                } else {
                    tokensWithIssues[issueCount] = config.collateralConfig.tokenAddr;
                    issueCount++;
                }

                tokenChecked[config.collateralConfig.tokenAddr] = true;
            }
        }

        // Summary report
        console.log("");
        console.log("=== SUMMARY REPORT ===");
        console.log("Total tokens checked: %d", successCount + issueCount);
        console.log("Successful: %d", successCount);
        console.log("Issues: %d", issueCount);

        // Detailed diagnostics for tokens with issues
        if (diagnostics.length > 0) {
            console.log("");
            console.log("=== DETAILED DIAGNOSTICS ===");
            for (uint256 i = 0; i < diagnostics.length; i++) {
                TokenDiagnostics memory diag = diagnostics[i];
                console.log("%d. %s (%s)", i + 1, diag.symbol, diag.tokenAddr);
                console.log("   Price Feed Address: %s", diag.priceFeedAddr);
                console.log("   Error Type: %s", diag.errorType);
                console.log("   Error Message: %s", diag.errorMessage);
                console.log("   Direct Price Feed Working: %s", diag.aggregatorWorks ? "YES" : "NO");
                console.log("   Oracle.getPrice Working: %s", diag.oracleWorks ? "YES" : "NO");

                if (diag.aggregatorWorks) {
                    console.log("   Raw Answer: %d", diag.rawAnswer);
                    console.log("   Price Feed Decimals: %d", diag.priceFeedDecimals);
                    console.log(
                        "   Last Update Time: %d (%s ago)",
                        diag.lastUpdateTime,
                        formatTimeDifference(block.timestamp - diag.lastUpdateTime)
                    );
                }

                console.log("   Token Decimals: %d", diag.tokenDecimals);
                console.log("   ---");
            }

            // Output recommendations based on the diagnostics
            console.log("");
            console.log("=== RECOMMENDATIONS ===");
            for (uint256 i = 0; i < diagnostics.length; i++) {
                TokenDiagnostics memory diag = diagnostics[i];
                console.log("%d. %s (%s):", i + 1, diag.symbol, diag.tokenAddr);

                if (keccak256(bytes(diag.errorType)) == keccak256(bytes("NO_ORACLE"))) {
                    console.log("   Run SubmitOracles script to configure the oracle for this token");
                } else if (keccak256(bytes(diag.errorType)) == keccak256(bytes("PRICE_FEED_ERROR"))) {
                    if (!diag.aggregatorWorks) {
                        console.log("   Price feed is not accessible. Verify the price feed address is correct");
                        console.log("   and that the price feed is correctly deployed on %s", network);
                    } else {
                        console.log("   Price feed is accessible but there may be an issue with its integration.");
                        console.log("   Check that the price feed has the correct interface and decimals");
                    }
                } else if (keccak256(bytes(diag.errorType)) == keccak256(bytes("ORACLE_ERROR"))) {
                    console.log("   The OracleAggregator can't retrieve the price. Check if there's a mismatch");
                    console.log(
                        "   between the price feed decimals (%d) and what OracleAggregator expects",
                        diag.priceFeedDecimals
                    );
                } else if (keccak256(bytes(diag.errorType)) == keccak256(bytes("STALE_DATA"))) {
                    console.log(
                        "   Price feed data is stale. Last update was %s ago",
                        formatTimeDifference(block.timestamp - diag.lastUpdateTime)
                    );
                    console.log("   Consider updating the heartbeat setting or using a different price feed");
                }
                console.log("   ---");
            }
        }
    }

    function formatTimeDifference(uint256 timeDiff) internal pure returns (string memory) {
        if (timeDiff < 60) {
            return string(abi.encodePacked(vm.toString(timeDiff), " seconds"));
        } else if (timeDiff < 3600) {
            return string(abi.encodePacked(vm.toString(timeDiff / 60), " minutes"));
        } else if (timeDiff < 86400) {
            return string(abi.encodePacked(vm.toString(timeDiff / 3600), " hours"));
        } else {
            return string(abi.encodePacked(vm.toString(timeDiff / 86400), " days"));
        }
    }

    function checkTokenOracle(
        IOracle oracle,
        OracleAggregator oracleAggregator,
        address tokenAddr,
        address expectedPriceFeedAddr,
        uint32 expectedHeartbeat,
        string memory tokenType
    ) internal returns (bool success) {
        // Create a diagnostic entry in case of error
        TokenDiagnostics memory diag;
        diag.tokenAddr = tokenAddr;
        diag.priceFeedAddr = expectedPriceFeedAddr;

        // Get token symbol and decimals
        try IERC20Metadata(tokenAddr).symbol() returns (string memory symbol) {
            diag.symbol = symbol;
        } catch {
            diag.symbol = "Unknown";
        }

        try IERC20Metadata(tokenAddr).decimals() returns (uint8 decimals) {
            diag.tokenDecimals = decimals;
        } catch {
            diag.tokenDecimals = 0;
        }

        console.log("--- Checking %s: %s (%s) ---", tokenType, diag.symbol, tokenAddr);

        // Check if the oracle is configured
        (AggregatorV3Interface aggregator, AggregatorV3Interface backupAggregator, uint32 heartbeat) =
            oracleAggregator.oracles(tokenAddr);

        if (address(aggregator) == address(0)) {
            console.log("ERROR: No oracle configured for token");
            diag.errorType = "NO_ORACLE";
            diag.errorMessage = "No oracle configured for this token";
            diagnostics.push(diag);
            return false;
        }

        // Check if the configured aggregator matches expected
        console.log("Price Feed: %s", address(aggregator));
        console.log("Expected: %s", expectedPriceFeedAddr);
        if (address(aggregator) != expectedPriceFeedAddr) {
            console.log("WARNING: Configured price feed doesn't match expected");
        }

        // Check heartbeat
        console.log("Heartbeat: %s", heartbeat);
        console.log("Expected: %s", expectedHeartbeat);
        if (heartbeat != expectedHeartbeat) {
            console.log("WARNING: Configured heartbeat doesn't match expected");
        }

        // First check direct access to the price feed
        bool directPriceFeedWorks = false;
        int256 rawAnswer = 0;
        uint256 updatedAt = 0;

        try AggregatorV3Interface(aggregator).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256 startedAt, uint256 updateTime, uint80 answeredInRound
        ) {
            console.log("Direct price feed access successful");
            console.log("Round ID: %d", roundId);
            console.log("Raw Answer: %d", answer);

            // Get price feed decimals
            try AggregatorV3Interface(aggregator).decimals() returns (uint8 priceFeedDecimals) {
                console.log("Price Feed Decimals: %d", priceFeedDecimals);
                diag.priceFeedDecimals = priceFeedDecimals;
            } catch {
                console.log("WARNING: Failed to get price feed decimals");
                diag.priceFeedDecimals = 0;
            }

            // Calculate time since last update
            uint256 timeSinceUpdate = block.timestamp - updateTime;
            console.log("Last updated: %d (%s ago)", updateTime, formatTimeDifference(timeSinceUpdate));

            // Update diagnostics
            directPriceFeedWorks = true;
            diag.aggregatorWorks = true;
            diag.rawAnswer = answer;
            diag.lastUpdateTime = updateTime;

            // Check if update is stale (beyond heartbeat)
            if (timeSinceUpdate > heartbeat) {
                console.log(
                    "WARNING: Price feed is stale (last updated %s ago, heartbeat is %d seconds)",
                    formatTimeDifference(timeSinceUpdate),
                    heartbeat
                );
                if (success) {
                    diag.errorType = "STALE_DATA";
                    diag.errorMessage = string(
                        abi.encodePacked(
                            "Price feed data is stale (last updated ", formatTimeDifference(timeSinceUpdate), " ago)"
                        )
                    );
                }
            }

            rawAnswer = answer;
            updatedAt = updateTime;
        } catch {
            console.log("ERROR: Failed to get latest round data directly from price feed");
            diag.errorType = "PRICE_FEED_ERROR";
            diag.errorMessage = "Failed to access price feed directly";
            diag.aggregatorWorks = false;
            diagnostics.push(diag);
            success = false;
        }

        // Now try to get price through the oracle
        if (directPriceFeedWorks) {
            try oracle.getPrice(tokenAddr) returns (uint256 price, uint8 decimals) {
                console.log("Oracle.getPrice successful");
                console.log("Price: %d (decimals: %d)", price, decimals);
                diag.oracleWorks = true;
                success = true;
            } catch {
                console.log("ERROR: Failed to get price from oracle (even though price feed works directly)");
                diag.errorType = "ORACLE_ERROR";
                diag.errorMessage = "Price feed works directly but Oracle.getPrice fails";
                diag.oracleWorks = false;
                diagnostics.push(diag);
                success = false;
            }
        }

        console.log("--------------------------------");
        return success;
    }
}
