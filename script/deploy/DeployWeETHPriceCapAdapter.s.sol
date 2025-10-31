// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxWeETHPriceCapAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxWeETHPriceCapAdapter.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";

/**
 * @title DeployWeETHPriceCapAdapter
 * @notice Script to deploy TermMaxWeETHPriceCapAdapter on Ethereum mainnet
 * @dev This script deploys an adapter that wraps Aave's WeETHPriceCapAdapter
 *
 * Usage:
 *   forge script script/deploy/DeployWeETHPriceCapAdapter.s.sol:DeployWeETHPriceCapAdapter \
 *     --rpc-url $ETH_MAINNET_RPC_URL \
 *     --private-key $ETH_MAINNET_DEPLOYER_PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployWeETHPriceCapAdapter is DeployBaseV2 {
    // Aave's deployed WeETHPriceCapAdapter on Ethereum mainnet
    // Source: https://github.com/bgd-labs/aave-capo
    address constant AAVE_WEETH_PRICE_CAP_ADAPTER = 0x87625393534d5C102cADB66D37201dF24cc26d4C;

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
        console.log("Aave WeETH Price Cap Adapter:", AAVE_WEETH_PRICE_CAP_ADAPTER);
    }

    function run() public {
        console.log("\n===== Starting Deployment =====");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TermMaxWeETHPriceCapAdapter
        TermMaxWeETHPriceCapAdapter adapter = new TermMaxWeETHPriceCapAdapter(AAVE_WEETH_PRICE_CAP_ADAPTER);

        vm.stopBroadcast();

        console.log("\n===== Deployment Successful =====");
        console.log("TermMaxWeETHPriceCapAdapter deployed at:", address(adapter));
        console.log("Wrapping Aave adapter at:", AAVE_WEETH_PRICE_CAP_ADAPTER);

        // Verify adapter configuration
        console.log("\n===== Verifying Adapter Configuration =====");
        console.log("Decimals:", adapter.decimals());
        console.log("Description:", adapter.description());

        // Get price data
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();
        console.log("\n===== Price Data =====");
        console.log("Round ID:", roundId);
        console.log("Answer (weETH/USD):", answer);
        console.log("Price in USD:", uint256(answer) / 1e8);
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
                '    "termMaxWeETHPriceCapAdapter": "',
                vm.toString(adapterAddress),
                '",\n',
                '    "aaveWeETHPriceCapAdapter": "',
                vm.toString(AAVE_WEETH_PRICE_CAP_ADAPTER),
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
            "-weeth-price-cap-adapter-",
            vm.toString(block.timestamp),
            ".json"
        );
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
