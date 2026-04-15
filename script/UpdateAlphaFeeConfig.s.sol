// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./deploy/DeployBaseV2.s.sol";

contract UpdateAlphaFeeConfig is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address[] alphaMarkets;

    FeeConfig alphaFeeConfig;
    uint32 mintGtFeeRatio = 0.1e8;
    uint32 mintGtFeeRef = 5e8;

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

        // Define alpha markets to update
        // Read markets from JSON file
        string memory marketsPath = string.concat(
            vm.projectRoot(), "/script/deploy/deploydata/", coreParams.network, "-alpha-market-addresses.json"
        );
        if (vm.exists(marketsPath)) {
            string memory marketsJson = vm.readFile(marketsPath);

            // Read alpha markets
            uint256 alphaTotal = vm.parseJsonUint(marketsJson, ".total");
            for (uint256 i = 0; i < alphaTotal; i++) {
                string memory key = string.concat(".market_", vm.toString(i), ".address");
                address marketAddr = vm.parseJsonAddress(marketsJson, key);
                alphaMarkets.push(marketAddr);
            }
            console.log("Loaded", alphaMarkets.length, "alpha markets from JSON");
        } else {
            console.log("Markets JSON file not found:", marketsPath);
        }
        alphaFeeConfig.mintGtFeeRatio = mintGtFeeRatio;
        alphaFeeConfig.mintGtFeeRef = mintGtFeeRef;
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Update stable markets fee config
        console.log("Updating fee config for", alphaMarkets.length, "alpha markets");
        for (uint256 i = 0; i < alphaMarkets.length; i++) {
            address market = alphaMarkets[i];
            console.log("Update alpha market:", market);
            MarketConfig memory config = TermMaxMarketV2(market).config();
            // check current fee config equals alphaFeeConfig to avoid unnecessary updates
            if (areFeeConfigsEqual(config.feeConfig, alphaFeeConfig)) {
                console.log("Fee config already up to date, skipping");
                continue;
            }
            config.feeConfig = alphaFeeConfig;
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

    function areFeeConfigsEqual(FeeConfig memory a, FeeConfig memory b) internal pure returns (bool) {
        return keccak256(abi.encode(a)) == keccak256(abi.encode(b));
    }
}
