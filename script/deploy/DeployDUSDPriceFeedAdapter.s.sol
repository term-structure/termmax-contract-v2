// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {TermMaxDUSDPriceFeedAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxDUSDPriceFeedAdapter.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";

/**
 * @title DeployDUSDPriceFeedAdapter
 * @notice Script to deploy TermMaxDUSDPriceFeedAdapter on Ethereum mainnet
 * @dev This script deploys an adapter that wraps the DUSD oracle
 *
 * Usage:
 *   forge script script/deploy/DeployDUSDPriceFeedAdapter.s.sol:DeployDUSDPriceFeedAdapter \
 *     --rpc-url $ETH_MAINNET_RPC_URL \
 *     --private-key $ETH_MAINNET_DEPLOYER_PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployDUSDPriceFeedAdapter is DeployBaseV2 {
    // Mainnet DUSD oracle + asset addresses (matching fork test)
    address constant DUSD_ORACLE = 0x49fba73738461835fefB19351b161Bde4BcD6b5A;
    address constant DUSD_ASSET = 0x871aB8E36CaE9AF35c6A3488B049965233DeB7ed;

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
        console.log("DUSD Oracle:", DUSD_ORACLE);
        console.log("DUSD Asset:", DUSD_ASSET);
    }

    function run() public {
        console.log("\n===== Starting Deployment =====");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TermMaxDUSDPriceFeedAdapter
        TermMaxDUSDPriceFeedAdapter adapter = new TermMaxDUSDPriceFeedAdapter(DUSD_ORACLE, DUSD_ASSET);

        vm.stopBroadcast();

        console.log("\n===== Deployment Successful =====");
        console.log("TermMaxDUSDPriceFeedAdapter deployed at:", address(adapter));
        console.log("Wrapped DUSD oracle:", DUSD_ORACLE);
        console.log("Asset tracked:", DUSD_ASSET);

        // Verify adapter configuration
        console.log("\n===== Verifying Adapter Configuration =====");
        console.log("Decimals:", adapter.decimals());
        console.log("Description:", adapter.description());

        // Get price data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();
        console.log("\n===== Price Data =====");
        console.log("Round ID:", roundId);
        console.log("Answer (DUSD/USDC with 18 decimals):", answer);
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
                '    "termMaxDETHPriceFeedAdapter": "',
                vm.toString(adapterAddress),
                '",\n',
                '    "dethOracle": "',
                vm.toString(DUSD_ORACLE),
                '",\n',
                '    "dethAsset": "',
                vm.toString(DUSD_ASSET),
                '"\n',
                "  }\n",
                "}"
            )
        );

        // Save to JSON file
        string memory jsonPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-deth-price-feed-adapter" ".json");
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
