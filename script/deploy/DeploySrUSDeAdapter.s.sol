// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxSparkLinearOracleAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxSparkLinearOracleAdapter.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";

/**
 * @title DeploySrUSDeAdapter
 * @notice Script to deploy TermMaxSparkLinearOracleAdapter for srUSDe on Ethereum mainnet
 * @dev This script deploys an adapter that wraps Spark/Pendle Linear Oracle for srUSDe
 *
 * Usage:
 *   forge script script/deploy/DeploySrUSDeAdapter.s.sol:DeploySrUSDeAdapter \
 *     --rpc-url $ETH_MAINNET_RPC_URL \
 *     --private-key $ETH_MAINNET_DEPLOYER_PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeploySrUSDeAdapter is DeployBaseV2 {
    // Spark/Pendle Linear Oracle for srUSDe on Ethereum mainnet
    // This oracle is already deployed and being used in the markets configuration
    address constant SPARK_SRUSDE_LINEAR_ORACLE = 0xeD2b85Df608fa9FBe95371D01566e12fb005EDeE;

    // Network configuration
    string network;
    address deployerAddr;
    uint256 deployerPrivateKey;
    bool isBroadcast;

    function setUp() public {
        // Load network configuration from environment variables
        network = vm.envOr("NETWORK", string("eth-mainnet"));
        isBroadcast = vm.envBool("IS_BROADCAST");
        string memory networkUpper = StringHelper.toUpper(network);

        // Load deployer private key
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);

        // Create deployments directory if it doesn't exist
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        console.log("===== Deployment Configuration =====");
        console.log("Network:", network);
        console.log("Deployer:", deployerAddr);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("Spark srUSDe Linear Oracle:", SPARK_SRUSDE_LINEAR_ORACLE);
    }

    function run() public {
        console.log("\n===== Starting Deployment =====");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TermMaxSparkLinearOracleAdapter
        TermMaxSparkLinearOracleAdapter adapter = new TermMaxSparkLinearOracleAdapter(SPARK_SRUSDE_LINEAR_ORACLE);

        vm.stopBroadcast();

        console.log("\n===== Deployment Successful =====");
        console.log("TermMaxSparkLinearOracleAdapter deployed at:", address(adapter));
        console.log("Wrapping Spark Linear Oracle at:", SPARK_SRUSDE_LINEAR_ORACLE);

        // Verify adapter configuration
        console.log("\n===== Verifying Adapter Configuration =====");
        console.log("Decimals:", adapter.decimals());
        console.log("Description:", adapter.description());
        console.log("Asset:", adapter.asset());

        // Get price data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();
        console.log("\n===== Price Data =====");
        console.log("Round ID:", roundId);
        console.log("Answer (srUSDe/USD):", answer);
        console.log("Price in USD:", uint256(answer) * 1e8 / (10 ** adapter.decimals()));
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
        console.log("Answered In Round:", answeredInRound);

        if (isBroadcast) {
            // Save deployment info
            saveDeploymentInfo(address(adapter));
        }
    }

    function saveDeploymentInfo(address adapterAddress) internal {
        console.log("\n===== Saving Deployment Info =====");

        // Get git info
        string memory gitBranch = getGitBranch();
        bytes memory gitCommitHash = getGitCommitHash();

        // Create JSON output
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                network,
                '",\n',
                '  "deployedAt": "',
                vm.toString(block.timestamp),
                '",\n',
                '  "gitBranch": "',
                gitBranch,
                '",\n',
                '  "gitCommitHash": "',
                vm.toString(gitCommitHash),
                '",\n',
                '  "blockInfo": {\n',
                '    "number": "',
                vm.toString(block.number),
                '",\n',
                '    "timestamp": "',
                vm.toString(block.timestamp),
                '"\n',
                "  },\n",
                '  "deployer": "',
                vm.toString(deployerAddr),
                '",\n',
                '  "contracts": {\n',
                '    "termMaxSparkLinearOracleAdapter": "',
                vm.toString(adapterAddress),
                '",\n',
                '    "sparkSrUSDeLinearOracle": "',
                vm.toString(SPARK_SRUSDE_LINEAR_ORACLE),
                '"\n',
                "  }\n",
                "}"
            )
        );

        // Save to JSON file
        string memory jsonPath = string.concat(
            vm.projectRoot(),
            "/deployments/",
            network,
            "/",
            network,
            "-srusde-spark-linear-adapter-",
            vm.toString(block.timestamp),
            ".json"
        );
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
