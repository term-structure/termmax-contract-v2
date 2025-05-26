// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {JsonLoader} from "./utils/JsonLoader.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {StringHelper} from "./utils/StringHelper.sol";
import {AccessManager} from "contracts/access/AccessManager.sol";

contract AcceptOracles is Script {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address oracleAggregatorAddr;
    address accessManagerAddr;
    JsonLoader.Config[] configs;
    mapping(address => bool) tokenChecked;

    // Track status of each oracle
    struct PendingOracleStatus {
        address tokenAddr;
        string tokenSymbol;
        address priceFeedAddr;
        address backupPriceFeedAddr;
        uint32 heartbeat;
        uint64 validAt;
        bool existsInConfig;
        bool pendingOracleExists;
        bool readyToAccept;
        string statusMessage;
    }

    PendingOracleStatus[] public acceptedOracles;
    PendingOracleStatus[] public notReadyOracles;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);
        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        deployerPrivateKey = vm.envUint(privateKeyVar);

        string memory accessManagerPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(accessManagerPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        string memory corePath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        json = vm.readFile(corePath);

        oracleAggregatorAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
    }

    function run() public {
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, ".json");

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        AccessManager accessManager = AccessManager(accessManagerAddr);
        OracleAggregator oracle = OracleAggregator(oracleAggregatorAddr);

        console.log("=== Checking Pending Oracles ===");
        console.log("Oracle Aggregator Address:", oracleAggregatorAddr);
        console.log("Network:", network);
        console.log("Current Block Timestamp:", block.timestamp);
        console.log("");

        // First, check all oracles for their status
        checkAllOracleStatus(oracle);

        // Only broadcast if there are oracles to accept
        if (acceptedOracles.length > 0) {
            vm.startBroadcast(deployerPrivateKey);

            // Process acceptances
            for (uint256 i = 0; i < acceptedOracles.length; i++) {
                PendingOracleStatus memory status = acceptedOracles[i];

                // Get current oracle config before accepting
                (AggregatorV3Interface currentAggregator,,) = oracle.oracles(status.tokenAddr);

                // Accept the oracle
                accessManager.acceptPendingOracle(oracle, status.tokenAddr);

                console.log("Accepted oracle for token:");
                console.log("  Token Symbol:", status.tokenSymbol);
                console.log("  Token Address:", status.tokenAddr);
                console.log("  Previous Oracle:", address(currentAggregator));
                console.log("  New Oracle:", status.priceFeedAddr);
                console.log("  Heartbeat:", status.heartbeat);
                console.log("--------------------------------");
            }

            vm.stopBroadcast();
        }

        // Print summary
        console.log("");
        console.log("=== Oracle Acceptance Summary ===");
        console.log("Total tokens checked:", acceptedOracles.length + notReadyOracles.length);
        console.log("Oracles accepted:", acceptedOracles.length);
        console.log("Oracles not ready:", notReadyOracles.length);

        if (notReadyOracles.length > 0) {
            console.log("");
            console.log("=== Oracles Not Ready for Acceptance ===");
            for (uint256 i = 0; i < notReadyOracles.length; i++) {
                PendingOracleStatus memory status = notReadyOracles[i];
                console.log("%d. %s (%s)", i + 1, status.tokenSymbol, status.tokenAddr);
                console.log("   Price Feed:", status.priceFeedAddr);
                console.log("   Backup Price Feed:", status.backupPriceFeedAddr);
                console.log("   Heartbeat:", status.heartbeat);
                console.log("   Status:", status.statusMessage);

                if (status.pendingOracleExists && status.validAt > 0) {
                    uint256 timeRemaining = status.validAt > block.timestamp ? status.validAt - block.timestamp : 0;
                    console.log("   Valid At:", status.validAt);
                    console.log("   Time Remaining:", formatTimeDifference(timeRemaining));
                    console.log("   Will be ready at:", formatTimestamp(status.validAt));
                }
                console.log("   ---");
            }
        }
    }

    function formatTimestamp(uint256 timestamp) internal pure returns (string memory) {
        return vm.toString(timestamp);
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

    function checkAllOracleStatus(OracleAggregator oracle) internal {
        // Process all tokens from the config
        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            // Check underlying token
            if (!tokenChecked[config.underlyingConfig.tokenAddr]) {
                checkAndReportOracleStatus(
                    oracle,
                    config.underlyingConfig.tokenAddr,
                    config.underlyingConfig.priceFeedAddr,
                    config.underlyingConfig.backupPriceFeedAddr,
                    uint32(config.underlyingConfig.heartBeat),
                    "underlying"
                );
                tokenChecked[config.underlyingConfig.tokenAddr] = true;
            }

            // Check collateral token
            if (!tokenChecked[config.collateralConfig.tokenAddr]) {
                checkAndReportOracleStatus(
                    oracle,
                    config.collateralConfig.tokenAddr,
                    config.collateralConfig.priceFeedAddr,
                    config.collateralConfig.backupPriceFeedAddr,
                    uint32(config.collateralConfig.heartBeat),
                    "collateral"
                );
                tokenChecked[config.collateralConfig.tokenAddr] = true;
            }
        }
    }

    function checkAndReportOracleStatus(
        OracleAggregator oracle,
        address tokenAddr,
        address expectedPriceFeedAddr,
        address expectedBackupPriceFeedAddr,
        uint32 expectedHeartbeat,
        string memory tokenType
    ) internal {
        // Create a new status entry
        PendingOracleStatus memory status;
        status.tokenAddr = tokenAddr;
        status.priceFeedAddr = expectedPriceFeedAddr;
        status.backupPriceFeedAddr = expectedBackupPriceFeedAddr;
        status.heartbeat = expectedHeartbeat;
        status.existsInConfig = true;

        // Get token symbol
        try IERC20Metadata(tokenAddr).symbol() returns (string memory symbol) {
            status.tokenSymbol = symbol;
        } catch {
            status.tokenSymbol = string(abi.encodePacked("Unknown ", tokenType));
        }

        // Check if there's a pending oracle
        (IOracle.Oracle memory pendingOracle, uint64 validAt) = oracle.pendingOracles(tokenAddr);

        // Get current oracle for comparison
        (
            AggregatorV3Interface currentAggregator,
            AggregatorV3Interface currentBackupAggregator,
            uint32 currentHeartbeat
        ) = oracle.oracles(tokenAddr);

        if (
            address(currentAggregator) == expectedPriceFeedAddr
                && address(currentBackupAggregator) == expectedBackupPriceFeedAddr && currentHeartbeat == expectedHeartbeat
        ) {
            status.readyToAccept = false;
            status.statusMessage = "Oracle is already configured with the correct values";
            notReadyOracles.push(status);
            return;
        } else if (
            address(pendingOracle.aggregator) == address(0) && address(pendingOracle.backupAggregator) == address(0)
                && pendingOracle.heartbeat == 0
        ) {
            // No pending oracle exists
            status.pendingOracleExists = false;
            status.readyToAccept = false;
            status.statusMessage = "No pending oracle exists";
            notReadyOracles.push(status);
        } else {
            // A pending oracle exists
            status.pendingOracleExists = true;
            status.validAt = validAt;

            // Check if it matches our expected price feed and is valid
            if (
                address(pendingOracle.aggregator) != expectedPriceFeedAddr
                    || address(pendingOracle.backupAggregator) != expectedBackupPriceFeedAddr
                    || pendingOracle.heartbeat != expectedHeartbeat
            ) {
                status.readyToAccept = false;
                status.statusMessage = string(
                    abi.encodePacked(
                        "Pending oracle doesn't match expected price feed. Found: ",
                        vm.toString(address(pendingOracle.aggregator)),
                        " Expected: ",
                        vm.toString(expectedPriceFeedAddr),
                        " Backup: ",
                        vm.toString(address(pendingOracle.backupAggregator)),
                        " Expected: ",
                        vm.toString(expectedBackupPriceFeedAddr),
                        " Heartbeat: ",
                        vm.toString(pendingOracle.heartbeat),
                        " Expected: ",
                        vm.toString(expectedHeartbeat)
                    )
                );
                notReadyOracles.push(status);
            } else if (validAt > block.timestamp) {
                // Timelock not yet elapsed
                status.readyToAccept = false;
                status.statusMessage = "Timelock period not yet elapsed";
                notReadyOracles.push(status);
            } else {
                // Oracle is ready to accept - this handles the case where the price feed address is different
                status.readyToAccept = true;

                // Add more detail to acceptance information
                if (address(currentAggregator) != expectedPriceFeedAddr) {
                    status.statusMessage = "Price feed address will be updated";
                } else {
                    // This branch should only be reached if there's some other condition
                    status.statusMessage = "Oracle will be updated (other changes)";
                }
                acceptedOracles.push(status);
                // Return here to avoid double-processing the same token
                return;
            }
        }
    }
}
