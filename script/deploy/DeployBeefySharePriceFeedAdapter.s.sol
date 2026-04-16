// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";
import {TermMaxBeefySharePriceFeedAdapter} from
    "contracts/v2/oracle/adapters/beefy/TermMaxBeefySharePriceFeedAdapter.sol";

/**
 * @title DeployBeefySharePriceFeedAdapter
 * @notice Script to deploy TermMaxBeefySharePriceFeedAdapter
 * @dev Env vars:
 *      - NETWORK (default: eth-mainnet)
 *      - {NETWORK}_DEPLOYER_PRIVATE_KEY
 *      - {NETWORK}_BEEFY_ADAPTER_COUNT (optional, default: 1)
 *
 *      Single deploy mode (count = 1):
 *      - {NETWORK}_BEEFY_VAULT (optional, fallback to fork-test value)
 *      - {NETWORK}_TOKEN0_PRICE_FEED (optional, fallback to fork-test value)
 *      - {NETWORK}_TOKEN1_PRICE_FEED (optional, fallback to fork-test value)
 *
 *      Batch deploy mode (count > 1):
 *      - {NETWORK}_BEEFY_VAULT_{i}
 *      - {NETWORK}_TOKEN0_PRICE_FEED_{i}
 *      - {NETWORK}_TOKEN1_PRICE_FEED_{i}
 *      where i = 0..count-1
 */
contract DeployBeefySharePriceFeedAdapter is DeployBaseV2 {
    address constant DEFAULT_BEEFY_VAULT = 0xAf92a4C7FCBc0Af09CfFf66d36C615fB40Ac1eEE;
    address constant DEFAULT_TOKEN0_PRICE_FEED = 0xbbF121624c3b85C929Ac83872bf6c86b0976A55e; // usde/usd
    address constant DEFAULT_TOKEN1_PRICE_FEED = 0x2D4f3199a80b848F3d094745F3Bbd4224892654e; // honey/usd

    address constant DEFAULT_BEEFY_VAULT_1 = 0x64606Bee7e4F5f67414765C4290315d3830ae0e2;
    address constant DEFAULT_TOKEN0_PRICE_FEED_1 = 0xEC352BC99BD444E0AC7f00e9B7D581B4b100CA3e; // susde/usd
    address constant DEFAULT_TOKEN1_PRICE_FEED_1 = 0x2D4f3199a80b848F3d094745F3Bbd4224892654e; // honey/usd
    uint256 public adapterCount = 2;

    string public network;
    address public deployerAddr;
    uint256 public deployerPrivateKey;

    address[] public beefyVaults;
    address[] public token0PriceFeeds;
    address[] public token1PriceFeeds;
    address[] public deployedAdapters;

    function setUp() public {
        network = vm.envOr("NETWORK", string("eth-mainnet"));
        string memory networkUpper = StringHelper.toUpper(network);

        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);

        beefyVaults = new address[](adapterCount);
        token0PriceFeeds = new address[](adapterCount);
        token1PriceFeeds = new address[](adapterCount);
        deployedAdapters = new address[](adapterCount);

        beefyVaults[0] = vm.envOr(string.concat(networkUpper, "_BEEFY_VAULT"), DEFAULT_BEEFY_VAULT);
        token0PriceFeeds[0] = vm.envOr(string.concat(networkUpper, "_TOKEN0_PRICE_FEED"), DEFAULT_TOKEN0_PRICE_FEED);
        token1PriceFeeds[0] = vm.envOr(string.concat(networkUpper, "_TOKEN1_PRICE_FEED"), DEFAULT_TOKEN1_PRICE_FEED);

        beefyVaults[1] = vm.envOr(string.concat(networkUpper, "_BEEFY_VAULT_1"), DEFAULT_BEEFY_VAULT_1);
        token0PriceFeeds[1] = vm.envOr(string.concat(networkUpper, "_TOKEN0_PRICE_FEED_1"), DEFAULT_TOKEN0_PRICE_FEED_1);
        token1PriceFeeds[1] = vm.envOr(string.concat(networkUpper, "_TOKEN1_PRICE_FEED_1"), DEFAULT_TOKEN1_PRICE_FEED_1);

        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        console.log("===== Deployment Configuration =====");
        console.log("Network:", network);
        console.log("Deployer:", deployerAddr);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("Adapter count:", adapterCount);
        for (uint256 i = 0; i < adapterCount; i++) {
            console.log("--- Adapter index:", i);
            console.log("Beefy Vault:", beefyVaults[i]);
            console.log("Token0 Price Feed:", token0PriceFeeds[i]);
            console.log("Token1 Price Feed:", token1PriceFeeds[i]);
        }
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        for (uint256 i = 0; i < adapterCount; i++) {
            TermMaxBeefySharePriceFeedAdapter adapter =
                new TermMaxBeefySharePriceFeedAdapter(beefyVaults[i], token0PriceFeeds[i], token1PriceFeeds[i]);
            deployedAdapters[i] = address(adapter);
        }
        vm.stopBroadcast();

        console.log("===== Deployment Successful =====");
        for (uint256 i = 0; i < adapterCount; i++) {
            TermMaxBeefySharePriceFeedAdapter adapter = TermMaxBeefySharePriceFeedAdapter(deployedAdapters[i]);
            console.log("--- Adapter index:", i);
            console.log("TermMaxBeefySharePriceFeedAdapter:", address(adapter));
            console.log("Description:", adapter.description());
            console.log("Decimals:", adapter.decimals());

            (, int256 answer,, uint256 updatedAt,) = adapter.latestRoundData();
            console.log("Latest Price:", answer);
            console.log("Updated At:", updatedAt);
        }

        saveDeploymentInfo();
    }

    function saveDeploymentInfo() internal {
        string memory adaptersJson = "";
        for (uint256 i = 0; i < adapterCount; i++) {
            if (i > 0) {
                adaptersJson = string.concat(adaptersJson, ",\n");
            }
            adaptersJson = string.concat(
                adaptersJson,
                "    {\n",
                '      "index": "',
                vm.toString(i),
                '",\n',
                '      "termMaxBeefySharePriceFeedAdapter": "',
                vm.toString(deployedAdapters[i]),
                '",\n',
                '      "beefyVault": "',
                vm.toString(beefyVaults[i]),
                '",\n',
                '      "token0PriceFeed": "',
                vm.toString(token0PriceFeeds[i]),
                '",\n',
                '      "token1PriceFeed": "',
                vm.toString(token1PriceFeeds[i]),
                '"\n',
                "    }"
            );
        }

        string memory json = string.concat(
            "{\n",
            '  "network": "',
            network,
            '",\n',
            '  "deployedAt": "',
            vm.toString(block.timestamp),
            '",\n',
            '  "gitBranch": "',
            getGitBranch(),
            '",\n',
            '  "gitCommitHash": "',
            vm.toString(getGitCommitHash()),
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
            '  "adapterCount": "',
            vm.toString(adapterCount),
            '",\n',
            '  "contracts": [\n',
            adaptersJson,
            "\n  ]\n",
            "}"
        );

        string memory jsonPath = string.concat(
            vm.projectRoot(), "/deployments/", network, "/", network, "-beefy-share-price-feed-adapter.json"
        );
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
