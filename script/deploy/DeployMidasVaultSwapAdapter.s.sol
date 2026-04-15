// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployBaseV2, AccessManagerV2, UUPSUpgradeable} from "./DeployBaseV2.s.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {KodiakSwapAdapter} from "contracts/v2/router/swapAdapters/KodiakSwapAdapter.sol";
import {LifiSwapAdapter} from "contracts/v2/router/swapAdapters/LifiSwapAdapter.sol";
import {OdosV2AdapterV2} from "contracts/v2/router/swapAdapters/OdosV2AdapterV2.sol";
import {OkxSwapAdapter} from "contracts/v2/router/swapAdapters/OkxSwapAdapter.sol";
import {OndoSwapAdapter} from "contracts/v2/router/swapAdapters/OndoSwapAdapter.sol";
import {OneInchSwapAdapter} from "contracts/v2/router/swapAdapters/OneInchSwapAdapter.sol";
import {PancakeSmartAdapter} from "contracts/v2/router/swapAdapters/PancakeSmartAdapter.sol";
import {PendleSwapV3AdapterV2} from "contracts/v2/router/swapAdapters/PendleSwapV3AdapterV2.sol";
import {TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {UniswapV3AdapterV2} from "contracts/v2/router/swapAdapters/UniswapV3AdapterV2.sol";
import {IWhitelistManager} from "contracts/v2/access/IWhitelistManager.sol";
import {TerminalVaultAdapter} from "contracts/v2/router/swapAdapters/TerminalVaultAdapter.sol";

contract DeployMidasVaultSwapAdapter is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address adapter;
    bool isBroadcast = vm.envBool("IS_BROADCAST");

    string deploymentPath;

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

        deploymentPath = string.concat(
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

        deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core.json");

        console.log("Using existing RouterV1 at:", address(coreContracts.routerV1));
        console.log("Using existing RouterV2 at:", address(coreContracts.router));

        coreParams.adminAddr = adminAddr;
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        {
            TerminalVaultAdapter terminalVaultAdapter = new TerminalVaultAdapter();
            console.log("TerminalVaultAdapter deploy at:", address(terminalVaultAdapter));
            adapter = address(terminalVaultAdapter);
            coreContracts.terminalVaultAdapter = terminalVaultAdapter;
        }

        console.log("Whitelist adapters in AccessManagerV2");

        coreContracts.accessManager.setAdapterWhitelist(TermMaxRouter(address(coreContracts.routerV1)), adapter, true);

        address[] memory adapters = new address[](1);
        adapters[0] = adapter;

        coreContracts.accessManager.batchSetWhitelist(
            coreContracts.whitelistManager, adapters, IWhitelistManager.ContractModule.ADAPTER, true
        );

        console.log("All adapters whitelisted in AccessManagerV2");

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

        deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );
        writeAsJson(deploymentPath, coreParams, coreContracts);
    }
}
