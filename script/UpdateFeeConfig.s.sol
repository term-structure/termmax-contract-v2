// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./deploy/DeployBaseV2.s.sol";

contract UpdateFeeConfig is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address[] stableMarkets;
    address[] otherMarkets;

    // 0.08e8 for USDC/USDT/USDU stables debt token; 0.03e8 for other debt tokens
    uint32 stable_mintGtFeeRatio = 0.1e8;
    uint32 stable_mintGtFeeRef = 0.08e8;
    uint32 other_mintGtFeeRatio = 0.1e8;
    uint32 other_mintGtFeeRef = 0.03e8;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);

        coreParams.isMainnet = vm.envBool("IS_MAINNET");
        coreParams.isL2Network = vm.envBool("IS_L2");
        {
            // Create deployments directory if it doesn't exist
            string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", coreParams.network);
            if (!vm.exists(deploymentsDir)) {
                // Directory doesn't exist, create it
                vm.createDir(deploymentsDir, true);
            }
        }

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-access-manager.json"
        );
        string memory json = vm.readFile(deploymentPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );
        if (vm.exists(deploymentPath)) {
            json = vm.readFile(deploymentPath);
            coreContracts = readDeployData(json);
        }
        console.log("Using existing AccessManagerV2 at:", accessManagerAddr);
        coreContracts.accessManager = AccessManagerV2(accessManagerAddr);

        // Read markets from JSON file
        string memory marketsPath =
            string.concat(vm.projectRoot(), "/script/deploy/deploydata/", coreParams.network, "-market-addresses.json");
        if (vm.exists(marketsPath)) {
            string memory marketsJson = vm.readFile(marketsPath);

            // Read stable markets
            uint256 stableTotal = vm.parseJsonUint(marketsJson, ".stable.total");
            for (uint256 i = 0; i < stableTotal; i++) {
                string memory key = string.concat(".stable.market_", vm.toString(i), ".address");
                address marketAddr = vm.parseJsonAddress(marketsJson, key);
                stableMarkets.push(marketAddr);
            }
            console.log("Loaded", stableMarkets.length, "stable markets from JSON");

            // Read other markets
            uint256 otherTotal = vm.parseJsonUint(marketsJson, ".others.total");
            for (uint256 i = 0; i < otherTotal; i++) {
                string memory key = string.concat(".others.market_", vm.toString(i), ".address");
                address marketAddr = vm.parseJsonAddress(marketsJson, key);
                otherMarkets.push(marketAddr);
            }
            console.log("Loaded", otherMarkets.length, "other markets from JSON");
        } else {
            console.log("Markets JSON file not found:", marketsPath);
        }
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Update stable markets fee config
        console.log("Updating fee config for", stableMarkets.length, "stable markets");
        for (uint256 i = 0; i < stableMarkets.length; i++) {
            address market = stableMarkets[i];
            console.log("Update stable market:", market);
            MarketConfig memory config = TermMaxMarketV2(market).config();
            config.feeConfig.mintGtFeeRatio = stable_mintGtFeeRatio;
            config.feeConfig.mintGtFeeRef = stable_mintGtFeeRef;
            coreContracts.accessManager.updateMarketConfig(TermMaxMarketV2(market), config);
        }

        // Update other markets fee config
        console.log("Updating fee config for", otherMarkets.length, "other markets");
        for (uint256 i = 0; i < otherMarkets.length; i++) {
            address market = otherMarkets[i];
            console.log("Update other market:", market);
            MarketConfig memory config = TermMaxMarketV2(market).config();
            config.feeConfig.mintGtFeeRatio = other_mintGtFeeRatio;
            config.feeConfig.mintGtFeeRef = other_mintGtFeeRef;
            coreContracts.accessManager.updateMarketConfig(TermMaxMarketV2(market), config);
        }

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log();

        console.log("===== Core Info =====");
        console.log("Deployer:", coreParams.deployerAddr);
        console.log("Admin:", adminAddr);
    }
}
