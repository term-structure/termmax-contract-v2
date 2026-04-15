// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";
import {UniversalFactory} from "contracts/v2/tokenomics/UniversalFactory.sol";

contract DeployTermMaxViewer is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;
    bool isBroadcast;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        isBroadcast = vm.envBool("IS_BROADCAST");
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);
        coreParams.adminAddr = adminAddr;
        {
            // Create deployments directory if it doesn't exist
            string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", coreParams.network);
            if (!vm.exists(deploymentsDir)) {
                // Directory doesn't exist, create it
                vm.createDir(deploymentsDir, true);
            }
        }
        coreParams.isMainnet = vm.envBool("IS_MAINNET");
        coreParams.isL2Network = vm.envBool("IS_L2");

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
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        if (coreContracts.termMaxViewer == TermMaxViewer(address(0))) {
            TermMaxViewer termMaxViewer = deployMarketViewer(address(coreContracts.accessManager));
            coreContracts.termMaxViewer = termMaxViewer;
            console.log("Deployed TermMaxViewer at:", address(termMaxViewer));
        } else {
            upgradeMarketViewer(coreContracts.accessManager, address(coreContracts.termMaxViewer));
            console.log("Upgraded TermMaxViewer at:", address(coreContracts.termMaxViewer));
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

        if (isBroadcast) {
            string memory deploymentPath = string.concat(
                vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
            );
            writeAsJson(deploymentPath, coreParams, coreContracts);
        }
    }
}
