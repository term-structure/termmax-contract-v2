// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./deploy/DeployBaseV2.s.sol";

contract UpgradeRouter is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

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
        if (address(coreContracts.router) == address(0)) {
            revert("RouterV2 not deployed");
        }
        console.log("Using existing RouterV2 at:", address(coreContracts.router));
        console.log("Using existing WhitelistManager at:", address(coreContracts.whitelistManager));
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        TermMaxRouterV2 routerV2 = new TermMaxRouterV2(address(coreContracts.whitelistManager));
        console.log("Deployed new RouterV2 implementation at:", address(routerV2));

        // Generate router upgrade data for the Safe wallet.
        bytes memory upgradeData = "";
        bytes memory upgradeCalldata = abi.encodeCall(
            AccessManagerV2.upgradeSubContract,
            (UUPSUpgradeable(address(coreContracts.router)), address(routerV2), upgradeData)
        );
        string memory upgradeAbi = string.concat(
            "{\"inputs\":[",
            "{\"internalType\":\"contract UUPSUpgradeable\",\"name\":\"proxy\",\"type\":\"address\"},",
            "{\"internalType\":\"address\",\"name\":\"newImplementation\",\"type\":\"address\"},",
            "{\"internalType\":\"bytes\",\"name\":\"data\",\"type\":\"bytes\"}",
            "],\"name\":\"upgradeSubContract\",\"outputs\":[],\"stateMutability\":\"nonpayable\",",
            "\"type\":\"function\"}"
        );

        console.log("===== Safe Wallet Router Upgrade Data =====");
        console.log("To (AccessManagerV2):", address(coreContracts.accessManager));
        console.log("Value: 0");
        console.log("ABI:");
        console.log(upgradeAbi);
        console.log("Router proxy:", address(coreContracts.router));
        console.log("New implementation:", address(routerV2));
        console.log("Upgrade data:");
        console.logBytes(upgradeData);
        console.log("Calldata:");
        console.logBytes(upgradeCalldata);

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
