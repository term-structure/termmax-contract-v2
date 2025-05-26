// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PreTMX} from "contracts/tokenomics/PreTMX.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DeployPreTMX is DeployBase {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer:", deployerAddr);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("Admin:", adminAddr);

        uint256 currentBlock = block.number;
        uint256 currentTimestamp = block.timestamp;

        vm.startBroadcast(deployerPrivateKey);
        PreTMX preTMX = deployPreTMX(adminAddr);
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", currentBlock);
        console.log("Block timestamp:", currentTimestamp);
        console.log();

        console.log("===== PreTMX Token Info =====");
        console.log("PreTMX deployed at:", address(preTMX));
        console.log("Token name:", preTMX.name());
        console.log("Token symbol:", preTMX.symbol());
        console.log("Total supply:", preTMX.totalSupply());
        console.log("Owner:", preTMX.owner());
        console.log("Transfer restricted:", preTMX.transferRestricted());
        console.log();

        // Write deployment results to a JSON file
        string memory deploymentJson = string(
            abi.encodePacked(
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
                '  "gitCommitHash": "0x',
                vm.toString(getGitCommitHash()),
                '",\n',
                '  "blockInfo": {\n',
                '    "number": "',
                vm.toString(currentBlock),
                '",\n',
                '    "timestamp": "',
                vm.toString(currentTimestamp),
                '"\n',
                "  },\n",
                '  "deployer": "',
                vm.toString(deployerAddr),
                '",\n',
                '  "admin": "',
                vm.toString(adminAddr),
                '",\n',
                '  "contracts": {\n',
                '    "preTMX": {\n',
                '      "address": "',
                vm.toString(address(preTMX)),
                '",\n',
                '      "name": "',
                preTMX.name(),
                '",\n',
                '      "symbol": "',
                preTMX.symbol(),
                '",\n',
                '      "totalSupply": "',
                vm.toString(preTMX.totalSupply()),
                '",\n',
                '      "owner": "',
                vm.toString(preTMX.owner()),
                '",\n',
                '      "transferRestricted": ',
                preTMX.transferRestricted() ? "true" : "false",
                "\n",
                "    }\n",
                "  }\n",
                "}"
            )
        );

        // Create deployment directory if it doesn't exist
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        // Write the JSON file with date suffix
        string memory filePath = getDeploymentFilePath(network, "pretmx");
        vm.writeFile(filePath, deploymentJson);
        console.log("Deployment information written to:", filePath);
    }

    function deployPreTMX(address admin) public returns (PreTMX preTMX) {
        console.log("Deploying PreTMX with admin:", admin);
        preTMX = new PreTMX(admin);
        console.log("PreTMX deployed successfully at:", address(preTMX));
        return preTMX;
    }
}
