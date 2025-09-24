// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployCoreV2 is DeployBaseV2 {
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

        coreParams.isMainnet = keccak256(abi.encodePacked(coreParams.network))
            == keccak256(abi.encodePacked("eth-mainnet"))
            || keccak256(abi.encodePacked(coreParams.network)) == keccak256(abi.encodePacked("arb-mainnet"))
            || keccak256(abi.encodePacked(coreParams.network)) == keccak256(abi.encodePacked("bnb-mainnet"));
        coreParams.isL2Network = (
            keccak256(abi.encodePacked(toUpper(coreParams.network))) == keccak256(abi.encodePacked("arb-mainnet"))
        ) || (keccak256(abi.encodePacked(toUpper(coreParams.network))) == keccak256(abi.encodePacked("arb-sepolia")));
        if (coreParams.isMainnet) {
            string memory uniswapV3RouterVar = string.concat(networkUpper, "_UNISWAP_V3_ROUTER_ADDRESS");
            string memory odosV2RouterVar = string.concat(networkUpper, "_ODOS_V2_ROUTER_ADDRESS");
            string memory pendleSwapV3RouterVar = string.concat(networkUpper, "_PENDLE_SWAP_V3_ROUTER_ADDRESS");
            string memory oracleTimelockVar = string.concat(networkUpper, "_ORACLE_TIMELOCK");
            coreParams.uniswapV3Router = vm.envAddress(uniswapV3RouterVar);
            coreParams.odosV2Router = vm.envAddress(odosV2RouterVar);
            coreParams.pendleSwapV3Router = vm.envAddress(pendleSwapV3RouterVar);
            coreParams.oracleTimelock = vm.envUint(oracleTimelockVar);
        }
        if (coreParams.isL2Network) {
            string memory l2SequencerUptimeFeedVar = string.concat(networkUpper, "_L2_SEQUENCER_UPTIME_FEED");
            coreParams.l2SequencerUpPriceFeed = vm.envAddress(l2SequencerUptimeFeedVar);
            string memory l2SequencerGracePeriodVar = string.concat(networkUpper, "_L2_SEQUENCER_GRACE_PERIOD");
            coreParams.l2GracePeriod = vm.envUint(l2SequencerGracePeriodVar);
        }
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
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManagerV2");

        deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core.json");
        if (vm.exists(deploymentPath)) {
            json = vm.readFile(deploymentPath);
            if (vm.keyExistsJson(json, ".contracts.router")) {
                address routerAddr = vm.parseJsonAddress(json, ".contracts.router");
                console.log("Router already deployed at:", routerAddr);
                coreContracts.router = TermMaxRouterV2(routerAddr);
            }
            if (vm.keyExistsJson(json, ".contracts.faucet")) {
                address faucetAddr = vm.parseJsonAddress(json, ".contracts.faucet");
                console.log("Faucet already deployed at:", faucetAddr);
                coreContracts.faucet = Faucet(faucetAddr);
            }
            if (vm.keyExistsJson(json, ".contracts.marketViewer")) {
                address marketViewerAddr = vm.parseJsonAddress(json, ".contracts.marketViewer");
                console.log("MarketViewer already deployed at:", marketViewerAddr);
                coreContracts.marketViewer = MarketViewer(marketViewerAddr);
            }
        }
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        coreContracts = deployCore(coreContracts, coreParams);
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
        console.log("AccessManagerV2 deployed at:", accessManagerAddr);
        console.log("WhitelistManager deployed at:", address(coreContracts.whitelistManager));
        console.log("FactoryV2 deployed at:", address(coreContracts.factory));
        console.log("VaultFactoryV2 deployed at:", address(coreContracts.vaultFactory));
        console.log("PriceFeedFactoryV2 deployed at:", address(coreContracts.priceFeedFactory));
        console.log("TermMax4626Factory deployed at:", address(coreContracts.tmx4626Factory));
        console.log("OracleAggregatorV2 deployed at:", address(coreContracts.oracle));
        console.log("RouterV2 deployed at:", address(coreContracts.router));
        console.log("MakerHelper deployed at:", address(coreContracts.makerHelper));
        console.log("MarketViewer deployed at:", address(coreContracts.marketViewer));
        if (coreParams.isMainnet) {
            console.log("UniswapV3AdapterV2 deployed at:", address(coreContracts.uniswapV3Adapter));
            console.log("OdosV2AdapterV2 deployed at:", address(coreContracts.odosV2Adapter));
            console.log("PendleSwapV3AdapterV2 deployed at:", address(coreContracts.pendleSwapV3Adapter));
            console.log("ERC4626VaultAdapterV2 deployed at:", address(coreContracts.vaultAdapter));
        } else {
            console.log("Faucet deployed at:", address(coreContracts.faucet));
            console.log("SwapAdapterV2 deployed at:", address(coreContracts.swapAdapter));
        }
        console.log("TermMaxSwapAdapter deployed at:", address(coreContracts.termMaxSwapAdapter));

        writeAsJson();
    }

    function writeAsJson() internal {
        // Write deployment results to a JSON file with timestamp
        string memory deploymentJson;

        {
            deploymentJson = string(
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
                    '  "gitCommitHash": "0x',
                    vm.toString(getGitCommitHash()),
                    '",\n',
                    '  "blockInfo": {\n',
                    '    "number": "',
                    vm.toString(block.number),
                    '",\n',
                    '    "timestamp": "',
                    vm.toString(block.timestamp),
                    '"\n',
                    "  },\n"
                )
            );
        }
        {
            deploymentJson = string(
                abi.encodePacked(
                    deploymentJson,
                    '  "deployer": "',
                    vm.toString(coreParams.deployerAddr),
                    '",\n',
                    '  "admin": "',
                    vm.toString(adminAddr),
                    '",\n',
                    '  "contracts": {\n',
                    '    "factoryV2": "',
                    vm.toString(address(coreContracts.factory)),
                    '",\n',
                    '    "vaultFactoryV2": "',
                    vm.toString(address(coreContracts.vaultFactory)),
                    '",\n',
                    '    "priceFeedFactoryV2": "',
                    vm.toString(address(coreContracts.priceFeedFactory)),
                    '",\n',
                    '    "termMax4626Factory": "',
                    vm.toString(address(coreContracts.tmx4626Factory)),
                    '",\n',
                    '    "whitelistManager": "',
                    vm.toString(address(coreContracts.whitelistManager)),
                    '",\n',
                    '    "oracleAggregatorV2": "',
                    vm.toString(address(coreContracts.oracle)),
                    '",\n',
                    '    "routerV2": "',
                    vm.toString(address(coreContracts.router)),
                    '",\n',
                    '    "MarketViewer": "',
                    vm.toString(address(coreContracts.marketViewer)),
                    '",\n',
                    '    "makerHelper": "',
                    vm.toString(address(coreContracts.makerHelper)),
                    '",\n',
                    '    "swapAdapterV2": '
                )
            );
        }

        {
            deploymentJson = string(
                abi.encodePacked(
                    deploymentJson,
                    coreParams.isMainnet
                        ? string.concat(
                            "{\n",
                            '      "uniswapV3AdapterV2": "',
                            vm.toString(address(coreContracts.uniswapV3Adapter)),
                            '",\n',
                            '      "odosV2AdapterV2": "',
                            vm.toString(address(coreContracts.odosV2Adapter)),
                            '",\n',
                            '      "pendleSwapV3AdapterV2": "',
                            vm.toString(address(coreContracts.pendleSwapV3Adapter)),
                            '",\n',
                            '      "ERC4626VaultAdapterV2": "',
                            vm.toString(address(coreContracts.vaultAdapter)),
                            '",\n',
                            '      "TermMaxSwapAdapter": "',
                            vm.toString(address(coreContracts.termMaxSwapAdapter)),
                            '"\n',
                            "    },\n"
                        )
                        : string.concat(
                            "{\n",
                            '      "swapAdapter": "',
                            vm.toString(address(coreContracts.swapAdapter)),
                            '",\n',
                            '      "TermMaxSwapAdapter": "',
                            vm.toString(address(coreContracts.termMaxSwapAdapter)),
                            '"\n',
                            "    },\n",
                            '    "faucet": "',
                            vm.toString(address(coreContracts.faucet)),
                            '",\n'
                        ),
                    '"\n',
                    "  }\n",
                    "}"
                )
            );
        }

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );

        vm.writeFile(deploymentPath, deploymentJson);
        console.log("Deployment info written to:", deploymentPath);
    }
}
