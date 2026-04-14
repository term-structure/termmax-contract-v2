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

contract DeployAllAdapter is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    string[] adapterNames;
    address[] adapters;
    string adaptersJson;
    bool isBroadcast = vm.envBool("IS_BROADCAST");

    string deploymentPath;

    address ondoGmTokenManager;
    address lifiRouter;
    address odosV2Router;
    address pendleRouter;
    address oneInchRouter;
    address pancakeRouter;

    bool isEth;
    bool isArb;
    bool isBnb;
    bool isBera;
    bool isHyper;
    bool isXlayer;
    bool isBase;
    bool isB2;
    bool isPharos;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        _getNetWork();
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

        {
            ondoGmTokenManager = vm.envOr(string.concat(networkUpper, "_ONDO_GM_MANAGER_ADDRESS"), address(0));
            console.log("Ondo GM Token Manager address:", ondoGmTokenManager);
            lifiRouter = vm.envOr(string.concat(networkUpper, "_LIFI_ROUTER_ADDRESS"), address(0));
            console.log("Lifi router address:", lifiRouter);
            odosV2Router = vm.envOr(string.concat(networkUpper, "_ODOS_V2_ROUTER_ADDRESS"), address(0));
            console.log("Odos V2 router address:", odosV2Router);
            pendleRouter = vm.envOr(string.concat(networkUpper, "_PENDLE_SWAP_V3_ROUTER_ADDRESS"), address(0));
            console.log("Pendle Swap V3 router address:", pendleRouter);
            pancakeRouter = vm.envOr(string.concat(networkUpper, "_PANCAKE_ROUTER_ADDRESS"), address(0));
            console.log("Pancake router address:", pancakeRouter);
            oneInchRouter = vm.envOr(string.concat(networkUpper, "_ONE_INCH_ROUTER_ADDRESS"), address(0));
            console.log("1inch router address:", oneInchRouter);
        }

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
            // termmax swap adapter
            TermMaxSwapAdapter termMaxSwapAdapter = new TermMaxSwapAdapter(address(coreContracts.whitelistManager));
            coreContracts.termMaxSwapAdapter = termMaxSwapAdapter;
            console.log("termMaxSwapAdapter deploy at:", address(termMaxSwapAdapter));
            adapters.push(address(termMaxSwapAdapter));
            adapterNames.push("termMaxSwapAdapter");

            // erc4626 vault adapter
            ERC4626VaultAdapterV2 erc4626Adapter = new ERC4626VaultAdapterV2();
            coreContracts.vaultAdapter = erc4626Adapter;
            console.log("ERC4626VaultAdapterV2 deploy at:", address(erc4626Adapter));
            adapters.push(address(erc4626Adapter));
            adapterNames.push("erc4626VaultAdapterV2");

            // kodiak swap adapter
            if (isBera) {
                KodiakSwapAdapter kodiakAdapter = new KodiakSwapAdapter();
                console.log("KodiakSwapAdapter deploy at:", address(kodiakAdapter));
                adapters.push(address(kodiakAdapter));
                adapterNames.push("kodiakSwapAdapter");
            }

            // lifi swap adapter
            if (isEth || isArb || isBnb || isBase) {
                require(lifiRouter != address(0), "Lifi router address is not set for this network");
                LifiSwapAdapter lifiAdapter = new LifiSwapAdapter(lifiRouter);
                console.log("LifiSwapAdapter deploy at:", address(lifiAdapter));
                adapters.push(address(lifiAdapter));
                adapterNames.push("lifiSwapAdapter");
            }

            // odos v2 adapter
            if (isEth || isArb || isBnb || isBase) {
                require(odosV2Router != address(0), "Odos V2 router address is not set for this network");
                OdosV2AdapterV2 odosAdapter = new OdosV2AdapterV2(odosV2Router);
                coreContracts.odosV2Adapter = odosAdapter;
                console.log("OdosV2AdapterV2 deploy at:", address(odosAdapter));
                adapters.push(address(odosAdapter));
                adapterNames.push("odosV2AdapterV2");
            }

            // okx swap adapter
            if (isEth || isArb || isBnb || isBase || isXlayer) {
                OkxSwapAdapter okxAdapter = new OkxSwapAdapter();
                console.log("OkxSwapAdapter deploy at:", address(okxAdapter));
                adapters.push(address(okxAdapter));
                adapterNames.push("okxSwapAdapter");
            }

            // ondo swap adapter
            if (isEth || isBnb) {
                require(ondoGmTokenManager != address(0), "Ondo GM Token Manager address is not set for this network");
                OndoSwapAdapter ondoAdapter = new OndoSwapAdapter(ondoGmTokenManager);
                console.log("OndoSwapAdapter deploy at:", address(ondoAdapter));
                adapters.push(address(ondoAdapter));
                adapterNames.push("ondoSwapAdapter");
            }
            // one inch swap adapter
            if (isEth || isArb || isBnb || isBase) {
                require(oneInchRouter != address(0), "1inch router address is not set for this network");
                OneInchSwapAdapter oneInchAdapter = new OneInchSwapAdapter(oneInchRouter);
                console.log("OneInchSwapAdapter deploy at:", address(oneInchAdapter));
                adapters.push(address(oneInchAdapter));
                adapterNames.push("oneInchSwapAdapter");
            }

            // pancake smart adapter
            if (isEth || isBnb) {
                require(pancakeRouter != address(0), "Pancake router address is not set for this network");
                PancakeSmartAdapter pancakeAdapter = new PancakeSmartAdapter(pancakeRouter);
                console.log("PancakeSmartAdapter deploy at:", address(pancakeAdapter));
                adapters.push(address(pancakeAdapter));
                adapterNames.push("pancakeSmartAdapter");
            }

            // pendle swap v3 adapter
            if (isEth || isArb || isBnb || isBase || isHyper || isBera) {
                require(pendleRouter != address(0), "Pendle router address is not set for this network");
                PendleSwapV3AdapterV2 pendleAdapter = new PendleSwapV3AdapterV2(pendleRouter);
                coreContracts.pendleSwapV3Adapter = pendleAdapter;
                console.log("PendleSwapV3AdapterV2 deploy at:", address(pendleAdapter));
                adapters.push(address(pendleAdapter));
                adapterNames.push("pendleSwapV3AdapterV2");
            }

            // uniswap v3 adapter only for b2 network
            if (isB2) {
                UniswapV3AdapterV2 uniswapV3Adapter = new UniswapV3AdapterV2();
                coreContracts.uniswapV3Adapter = uniswapV3Adapter;
                console.log("UniswapV3AdapterV2 deploy at:", address(uniswapV3Adapter));
                adapters.push(address(uniswapV3Adapter));
                adapterNames.push("uniswapV3AdapterV2");
            }
        }

        console.log("Whitelist adapters in AccessManagerV2");

        adaptersJson = "[\n";
        for (uint256 i = 0; i < adapters.length; i++) {
            adaptersJson = string.concat(
                adaptersJson,
                "      {\n",
                '        "name": "',
                adapterNames[i],
                '",\n',
                '        "address": "',
                vm.toString(adapters[i]),
                '"\n',
                "      }"
            );
            if (i != adapters.length - 1) {
                adaptersJson = string.concat(adaptersJson, ",\n");
            } else {
                adaptersJson = string.concat(adaptersJson, "\n");
            }
            coreContracts.accessManager.setAdapterWhitelist(
                TermMaxRouter(address(coreContracts.routerV1)), adapters[i], true
            );
        }
        adaptersJson = string.concat(adaptersJson, "    ]");
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

        string memory deploymentJson = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                coreParams.network,
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
                '  "contracts": {\n',
                '    "routerV1": "',
                vm.toString(address(coreContracts.routerV1)),
                '",\n',
                '    "router": "',
                vm.toString(address(coreContracts.router)),
                '",\n',
                '    "accessManager": "',
                vm.toString(address(coreContracts.accessManager)),
                '",\n',
                '    "adapters": ',
                adaptersJson,
                "\n  }\n",
                "}"
            )
        );
        string memory path =
            string.concat(vm.projectRoot(), "/deployments/", coreParams.network, "/", "all-adapters", ".json");

        vm.writeFile(path, deploymentJson);

        deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );
        writeAsJson(deploymentPath, coreParams, coreContracts);
    }

    function _getNetWork() internal {
        isEth = keccak256(bytes(coreParams.network)) == keccak256(bytes("eth-mainnet"));
        isArb = keccak256(bytes(coreParams.network)) == keccak256(bytes("arb-mainnet"));
        isBnb = keccak256(bytes(coreParams.network)) == keccak256(bytes("bnb-mainnet"));
        isBera = keccak256(bytes(coreParams.network)) == keccak256(bytes("bera-mainnet"));
        isHyper = keccak256(bytes(coreParams.network)) == keccak256(bytes("hyperevm-mainnet"));
        isXlayer = keccak256(bytes(coreParams.network)) == keccak256(bytes("xlayer-mainnet"));
        isBase = keccak256(bytes(coreParams.network)) == keccak256(bytes("base-mainnet"));
        isB2 = keccak256(bytes(coreParams.network)) == keccak256(bytes("b2-mainnet"));
        isPharos = keccak256(bytes(coreParams.network)) == keccak256(bytes("pharos-mainnet"));
    }
}
