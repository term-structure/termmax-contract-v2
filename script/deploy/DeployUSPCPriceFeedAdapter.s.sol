// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {TermMaxUSPCPriceFeedAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxUSPCPriceFeedAdapter.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";

/**
 * @title DeployUSPCPriceFeedAdapter
 * @notice Script to deploy TermMaxUSPCPriceFeedAdapter on B2 mainnet
 * @dev This script deploys an adapter that wraps the USPC oracle
 *
 * Usage:
 *   forge script script/deploy/DeployUSPCPriceFeedAdapter.s.sol:DeployUSPCPriceFeedAdapter \
 *     --rpc-url $B2_MAINNET_RPC_URL \
 *     --private-key $B2_MAINNET_DEPLOYER_PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployUSPCPriceFeedAdapter is DeployBaseV2 {
    // B2 mainnet USPC oracle + asset addresses
    address constant USPC_ORACLE = 0x5eC0C20A83554eC1BBC0F1D3414BB8746a04acD4;
    address constant USPC_ASSET = 0xdc807c3a618B6B1248481783def7ED76700B9eC6;

    // Network configuration
    string network;
    address deployerAddr;
    uint256 deployerPrivateKey;

    function setUp() public {
        // Load network configuration from environment variables
        network = vm.envOr("NETWORK", string("eth-mainnet"));
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
        console.log("USPC Oracle:", USPC_ORACLE);
        console.log("USPC Asset:", USPC_ASSET);
    }

    function run() public {
        console.log("\n===== Starting Deployment =====");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TermMaxUSPCPriceFeedAdapter
        TermMaxUSPCPriceFeedAdapter adapter = new TermMaxUSPCPriceFeedAdapter(USPC_ORACLE, USPC_ASSET);

        vm.stopBroadcast();

        console.log("\n===== Deployment Successful =====");
        console.log("TermMaxUSPCPriceFeedAdapter deployed at:", address(adapter));
        console.log("Wrapped USPC oracle:", USPC_ORACLE);
        console.log("Asset tracked:", USPC_ASSET);

        // Verify adapter configuration
        console.log("\n===== Verifying Adapter Configuration =====");
        console.log("Decimals:", adapter.decimals());
        console.log("Description:", adapter.description());

        // Get price data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();
        console.log("\n===== Price Data =====");
        console.log("Round ID:", roundId);
        console.log("Answer (USPC/USDC with 18 decimals):", answer);
        console.log("Price (human readable):", uint256(answer) / 1e18);
        console.log("Started At:", startedAt);
        console.log("Updated At:", updatedAt);
        console.log("Answered In Round:", answeredInRound);

        // Save deployment info
        saveDeploymentInfo(address(adapter));
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
                '    "termMaxUSPCPriceFeedAdapter": "',
                vm.toString(adapterAddress),
                '",\n',
                '    "uspcOracle": "',
                vm.toString(USPC_ORACLE),
                '",\n',
                '    "uspcAsset": "',
                vm.toString(USPC_ASSET),
                '"\n',
                "  }\n",
                "}"
            )
        );

        // Save to JSON file
        string memory jsonPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-uspc-price-feed-adapter.json");
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
