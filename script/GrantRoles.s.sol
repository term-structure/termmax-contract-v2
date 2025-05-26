// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {AccessManager} from "contracts/access/AccessManager.sol";
import {StringHelper} from "./utils/StringHelper.sol";
import {ScriptBase} from "./utils/ScriptBase.sol";

/**
 * @title GrantRoles
 * @notice Script to grant essential roles to the deployer address
 * @dev Uses admin private key to grant MARKET_ROLE, ORACLE_ROLE, and VAULT_ROLE
 *      to the deployer address for deploying and managing contracts
 */
contract GrantRoles is ScriptBase {
    // Network-specific config loaded from environment variables
    string network;
    uint256 adminPrivateKey;
    address adminAddr;
    address deployerAddr;
    address accessManagerAddr;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);

        // Load network-specific configuration
        string memory adminPrivateKeyVar = string.concat(networkUpper, "_ADMIN_PRIVATE_KEY");
        string memory deployerVar = string.concat(networkUpper, "_DEPLOYER_ADDRESS");

        adminPrivateKey = vm.envUint(adminPrivateKeyVar);
        adminAddr = vm.addr(adminPrivateKey);
        deployerAddr = vm.envAddress(deployerVar);

        // Load AccessManager address from deployment file
        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");
    }

    function run() public {
        console.log("=== Configuration ===");
        console.log("Network:", network);
        console.log("Admin:", adminAddr);
        console.log("Deployer:", deployerAddr);
        console.log("AccessManager:", accessManagerAddr);
        console.log("");

        console.log("=== Granting Roles to Deployer ===");

        vm.startBroadcast(adminPrivateKey);
        AccessManager accessManager = AccessManager(accessManagerAddr);

        // Grant MARKET_ROLE to deployer
        if (!accessManager.hasRole(accessManager.MARKET_ROLE(), deployerAddr)) {
            accessManager.grantRole(accessManager.MARKET_ROLE(), deployerAddr);
            console.log("[SUCCESS] MARKET_ROLE granted to deployer");
        } else {
            console.log("[INFO] Deployer already has MARKET_ROLE");
        }

        // Grant ORACLE_ROLE to deployer
        if (!accessManager.hasRole(accessManager.ORACLE_ROLE(), deployerAddr)) {
            accessManager.grantRole(accessManager.ORACLE_ROLE(), deployerAddr);
            console.log("[SUCCESS] ORACLE_ROLE granted to deployer");
        } else {
            console.log("[INFO] Deployer already has ORACLE_ROLE");
        }

        // Grant VAULT_ROLE to deployer
        if (!accessManager.hasRole(accessManager.VAULT_ROLE(), deployerAddr)) {
            accessManager.grantRole(accessManager.VAULT_ROLE(), deployerAddr);
            console.log("[SUCCESS] VAULT_ROLE granted to deployer");
        } else {
            console.log("[INFO] Deployer already has VAULT_ROLE");
        }

        // Grant CONFIGURATOR_ROLE to deployer (might be useful for additional config)
        if (!accessManager.hasRole(accessManager.CONFIGURATOR_ROLE(), deployerAddr)) {
            accessManager.grantRole(accessManager.CONFIGURATOR_ROLE(), deployerAddr);
            console.log("[SUCCESS] CONFIGURATOR_ROLE granted to deployer");
        } else {
            console.log("[INFO] Deployer already has CONFIGURATOR_ROLE");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Role Assignment Complete ===");
        console.log("The deployer address now has all necessary roles to deploy and manage contracts");

        // Generate execution results JSON
        uint256 currentBlock = block.number;
        uint256 currentTimestamp = block.timestamp;

        string memory baseJson = createBaseExecutionJson(network, "GrantRoles", currentBlock, currentTimestamp);

        // Check final role status
        bool hasMarketRole = accessManager.hasRole(accessManager.MARKET_ROLE(), deployerAddr);
        bool hasOracleRole = accessManager.hasRole(accessManager.ORACLE_ROLE(), deployerAddr);
        bool hasVaultRole = accessManager.hasRole(accessManager.VAULT_ROLE(), deployerAddr);
        bool hasConfiguratorRole = accessManager.hasRole(accessManager.CONFIGURATOR_ROLE(), deployerAddr);

        // Add script-specific data
        string memory executionJson = string(
            abi.encodePacked(
                baseJson,
                ",\n",
                '  "results": {\n',
                '    "adminAddress": "',
                vm.toString(adminAddr),
                '",\n',
                '    "deployerAddress": "',
                vm.toString(deployerAddr),
                '",\n',
                '    "accessManagerAddress": "',
                vm.toString(accessManagerAddr),
                '",\n',
                '    "rolesGranted": {\n',
                '      "MARKET_ROLE": ',
                hasMarketRole ? "true" : "false",
                ",\n",
                '      "ORACLE_ROLE": ',
                hasOracleRole ? "true" : "false",
                ",\n",
                '      "VAULT_ROLE": ',
                hasVaultRole ? "true" : "false",
                ",\n",
                '      "CONFIGURATOR_ROLE": ',
                hasConfiguratorRole ? "true" : "false",
                "\n",
                "    }\n",
                "  }\n",
                "}"
            )
        );

        writeScriptExecutionResults(network, "GrantRoles", executionJson);
    }
}
