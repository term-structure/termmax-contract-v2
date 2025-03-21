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

contract SubmitOracles is Script {
    // Network-specific config loaded from environment variables
    string network;
    uint256 oracleAggregatorAdminPrivateKey;
    address oracleAggregatorAddr;
    JsonLoader.Config[] configs;
    mapping(address => bool) tokenSubmitted;

    // Track status of each token submission
    struct OracleSubmissionStatus {
        address tokenAddr;
        string tokenSymbol;
        address currentPriceFeedAddr;
        address newPriceFeedAddr;
        uint32 currentHeartbeat;
        uint32 newHeartbeat;
        bool needsUpdate;
        string updateReason;
    }

    OracleSubmissionStatus[] public submittedOracles;
    OracleSubmissionStatus[] public skippedOracles;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);
        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY");
        oracleAggregatorAdminPrivateKey = vm.envUint(privateKeyVar);

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        string memory json = vm.readFile(deploymentPath);

        oracleAggregatorAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
    }

    function run() public {
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, ".json");
        string memory deployData = vm.readFile(deployDataPath);
        configs = JsonLoader.getConfigsFromJson(deployData);

        // First check all oracles and identify which ones need updates
        console.log("=== Checking Oracles for Updates ===");
        console.log("Oracle Aggregator Address:", oracleAggregatorAddr);
        console.log("Network:", network);
        console.log("");

        OracleAggregator oracle = OracleAggregator(oracleAggregatorAddr);
        checkAllOraclesForUpdates(oracle);

        // Only broadcast if there are oracles to submit
        if (submittedOracles.length > 0) {
            vm.startBroadcast(oracleAggregatorAdminPrivateKey);

            // Submit pending oracles
            for (uint256 i = 0; i < submittedOracles.length; i++) {
                OracleSubmissionStatus memory status = submittedOracles[i];

                // Submit the pending oracle
                oracle.submitPendingOracle(
                    status.tokenAddr,
                    IOracle.Oracle(
                        AggregatorV3Interface(status.newPriceFeedAddr),
                        AggregatorV3Interface(status.newPriceFeedAddr),
                        status.newHeartbeat
                    )
                );

                // Print submission details
                console.log("Submitted oracle for token:");
                console.log("  Token Symbol:", status.tokenSymbol);
                console.log("  Token Address:", status.tokenAddr);
                console.log("  Update Reason:", status.updateReason);

                if (status.currentPriceFeedAddr != status.newPriceFeedAddr) {
                    console.log("  Previous Price Feed:", status.currentPriceFeedAddr);
                    console.log("  New Price Feed:", status.newPriceFeedAddr);
                }

                if (status.currentHeartbeat != status.newHeartbeat) {
                    console.log("  Previous Heartbeat:", status.currentHeartbeat);
                    console.log("  New Heartbeat:", status.newHeartbeat);
                }

                console.log("--------------------------------");
            }

            vm.stopBroadcast();
        } else {
            console.log("No oracles need to be submitted.");
        }

        // Print summary
        console.log("");
        console.log("=== Oracle Submission Summary ===");
        console.log("Total tokens checked:", submittedOracles.length + skippedOracles.length);
        console.log("Oracles submitted:", submittedOracles.length);
        console.log("Oracles skipped:", skippedOracles.length);

        if (skippedOracles.length > 0) {
            console.log("");
            console.log("=== Skipped Oracles ===");
            for (uint256 i = 0; i < skippedOracles.length; i++) {
                OracleSubmissionStatus memory status = skippedOracles[i];
                console.log("%d. %s (%s)", i + 1, status.tokenSymbol, status.tokenAddr);
                console.log("   Current Price Feed:", status.currentPriceFeedAddr);
                console.log("   Current Heartbeat:", status.currentHeartbeat);
                console.log("   Reason Skipped:", status.updateReason);
                console.log("   ---");
            }
        }
    }

    function checkAllOraclesForUpdates(OracleAggregator oracle) internal {
        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            // Check underlying token
            if (!tokenSubmitted[config.underlyingConfig.tokenAddr]) {
                checkTokenOracleForUpdate(
                    oracle,
                    config.underlyingConfig.tokenAddr,
                    config.underlyingConfig.priceFeedAddr,
                    uint32(config.underlyingConfig.heartBeat),
                    "underlying"
                );
                tokenSubmitted[config.underlyingConfig.tokenAddr] = true;
            }

            // Check collateral token
            if (!tokenSubmitted[config.collateralConfig.tokenAddr]) {
                checkTokenOracleForUpdate(
                    oracle,
                    config.collateralConfig.tokenAddr,
                    config.collateralConfig.priceFeedAddr,
                    uint32(config.collateralConfig.heartBeat),
                    "collateral"
                );
                tokenSubmitted[config.collateralConfig.tokenAddr] = true;
            }
        }
    }

    function checkTokenOracleForUpdate(
        OracleAggregator oracle,
        address tokenAddr,
        address expectedPriceFeedAddr,
        uint32 expectedHeartbeat,
        string memory tokenType
    ) internal {
        // Create a status entry
        OracleSubmissionStatus memory status;
        status.tokenAddr = tokenAddr;
        status.newPriceFeedAddr = expectedPriceFeedAddr;
        status.newHeartbeat = expectedHeartbeat;

        // Get token symbol
        try IERC20Metadata(tokenAddr).symbol() returns (string memory symbol) {
            status.tokenSymbol = symbol;
        } catch {
            status.tokenSymbol = string(abi.encodePacked("Unknown ", tokenType));
        }

        // Get current oracle configuration
        (AggregatorV3Interface aggregator,, uint32 heartbeat) = oracle.oracles(tokenAddr);
        status.currentPriceFeedAddr = address(aggregator);
        status.currentHeartbeat = heartbeat;

        // Check if we need to submit a new oracle
        if (address(expectedPriceFeedAddr) == address(0)) {
            // Skip if no price feed is specified
            status.needsUpdate = false;
            status.updateReason = "No price feed specified in configuration";
            skippedOracles.push(status);
        } else if (address(aggregator) == address(0)) {
            // No oracle configured yet
            status.needsUpdate = true;
            status.updateReason = "No oracle currently configured";
            submittedOracles.push(status);
        } else if (address(aggregator) != expectedPriceFeedAddr && heartbeat != expectedHeartbeat) {
            // Both price feed and heartbeat need to be updated
            status.needsUpdate = true;
            status.updateReason = "Price feed address and heartbeat both need update";
            submittedOracles.push(status);
        } else if (address(aggregator) != expectedPriceFeedAddr) {
            // Only price feed needs to be updated
            status.needsUpdate = true;
            status.updateReason = "Price feed address needs update";
            submittedOracles.push(status);
        } else if (heartbeat != expectedHeartbeat) {
            // Only heartbeat needs to be updated
            status.needsUpdate = true;
            status.updateReason = "Heartbeat value needs update";
            submittedOracles.push(status);
        } else {
            // Oracle is already configured correctly
            status.needsUpdate = false;
            status.updateReason = "Oracle already correctly configured";
            skippedOracles.push(status);
        }
    }
}
