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

contract AcceptOracles is Script {
    // Network-specific config loaded from environment variables
    string network;
    uint256 oracleAggregatorAdminPrivateKey;
    address oracleAggregatorAddr;
    JsonLoader.Config[] configs;
    mapping(address => bool) tokenAccepted;

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

        OracleAggregator oracle = OracleAggregator(oracleAggregatorAddr);

        vm.startBroadcast(oracleAggregatorAdminPrivateKey);

        console.log("=== Accepting Pending Oracles ===");
        console.log("Oracle Aggregator Address:", oracleAggregatorAddr);
        console.log("Network:", network);
        console.log("");

        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            // Check for pending oracles on underlying token
            (AggregatorV3Interface currentAggregator,,) = oracle.oracles(address(config.underlyingConfig.tokenAddr));
            (IOracle.Oracle memory pendingOracle, uint64 validAt) =
                oracle.pendingOracles(address(config.underlyingConfig.tokenAddr));

            if (
                !tokenAccepted[address(config.underlyingConfig.tokenAddr)]
                    && address(pendingOracle.aggregator) != address(0)
                    && address(pendingOracle.aggregator) == address(config.underlyingConfig.priceFeedAddr)
                    && validAt <= block.timestamp
            ) {
                // Accept the pending oracle
                oracle.acceptPendingOracle(address(config.underlyingConfig.tokenAddr));
                tokenAccepted[address(config.underlyingConfig.tokenAddr)] = true;

                console.log("Accepted oracle for underlying token:");
                console.log("  Token:", IERC20Metadata(address(config.underlyingConfig.tokenAddr)).symbol());
                console.log("  Previous Oracle:", address(currentAggregator));
                console.log("  New Oracle:", address(pendingOracle.aggregator));
                console.log("  Heartbeat:", pendingOracle.heartbeat);
                console.log("--------------------------------");
            }

            // Check for pending oracles on collateral token
            (currentAggregator,,) = oracle.oracles(address(config.collateralConfig.tokenAddr));
            (pendingOracle, validAt) = oracle.pendingOracles(address(config.collateralConfig.tokenAddr));

            if (
                !tokenAccepted[address(config.collateralConfig.tokenAddr)]
                    && address(pendingOracle.aggregator) != address(0)
                    && address(pendingOracle.aggregator) == address(config.collateralConfig.priceFeedAddr)
                    && validAt <= block.timestamp
            ) {
                // Accept the pending oracle
                oracle.acceptPendingOracle(address(config.collateralConfig.tokenAddr));
                tokenAccepted[address(config.collateralConfig.tokenAddr)] = true;

                console.log("Accepted oracle for collateral token:");
                console.log("  Token:", IERC20Metadata(address(config.collateralConfig.tokenAddr)).symbol());
                console.log("  Previous Oracle:", address(currentAggregator));
                console.log("  New Oracle:", address(pendingOracle.aggregator));
                console.log("  Heartbeat:", pendingOracle.heartbeat);
                console.log("--------------------------------");
            }
        }
        vm.stopBroadcast();

        console.log("");
        console.log("Oracle acceptance process completed.");
    }
}
