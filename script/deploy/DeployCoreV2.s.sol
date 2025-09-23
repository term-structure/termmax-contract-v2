// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployCoreV2 is DeployBaseV2 {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;
    address accessManagerAddr;
    address uniswapV3RouterAddr;
    address odosV2RouterAddr;
    address pendleSwapV3RouterAddr;
    uint256 oracleTimelock;

    AccessManagerV2 accessManager;
    TermMaxFactoryV2 factory;
    TermMaxVaultFactoryV2 vaultFactory;
    OracleAggregatorV2 oracleAggregator;
    TermMaxRouterV2 router;
    MakerHelper makerHelper;
    MarketViewer marketViewer;
    UniswapV3AdapterV2 uniswapV3Adapter;
    OdosV2AdapterV2 odosV2Adapter;
    PendleSwapV3AdapterV2 pendleSwapV3Adapter;
    ERC4626VaultAdapterV2 vaultAdapter;
    TermMaxSwapAdapter termMaxSwapAdapter;
    SwapAdapterV2 swapAdapter;
    Faucet faucet;
    TermMaxPriceFeedFactoryV2 priceFeedFactory;

    address l2SequencerUptimeFeed;
    uint256 l2SequencerGracePeriod;

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

        if (
            keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("eth-mainnet"))
                || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))
                || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("bnb-mainnet"))
        ) {
            string memory uniswapV3RouterVar = string.concat(networkUpper, "_UNISWAP_V3_ROUTER_ADDRESS");
            string memory odosV2RouterVar = string.concat(networkUpper, "_ODOS_V2_ROUTER_ADDRESS");
            string memory pendleSwapV3RouterVar = string.concat(networkUpper, "_PENDLE_SWAP_V3_ROUTER_ADDRESS");
            string memory oracleTimelockVar = string.concat(networkUpper, "_ORACLE_TIMELOCK");
            uniswapV3RouterAddr = vm.envAddress(uniswapV3RouterVar);
            odosV2RouterAddr = vm.envAddress(odosV2RouterVar);
            pendleSwapV3RouterAddr = vm.envAddress(pendleSwapV3RouterVar);
            oracleTimelock = vm.envUint(oracleTimelockVar);

            if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))) {
                string memory l2SequencerUptimeFeedVar = string.concat(networkUpper, "_L2_SEQUENCER_UPTIME_FEED");
                l2SequencerUptimeFeed = vm.envAddress(l2SequencerUptimeFeedVar);
                string memory l2SequencerGracePeriodVar = string.concat(networkUpper, "_L2_SEQUENCER_GRACE_PERIOD");
                l2SequencerGracePeriod = vm.envUint(l2SequencerGracePeriodVar);
            }
        }
        {
            // Create deployments directory if it doesn't exist
            string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
            if (!vm.exists(deploymentsDir)) {
                // Directory doesn't exist, create it
                vm.createDir(deploymentsDir, true);
            }
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManagerV2");

        deploymentPath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        if (vm.exists(deploymentPath)) {
            json = vm.readFile(deploymentPath);
            if (vm.keyExistsJson(json, ".contracts.router")) {
                address routerAddr = vm.parseJsonAddress(json, ".contracts.router");
                console.log("Router already deployed at:", routerAddr);
                router = TermMaxRouterV2(routerAddr);
            }
            if (vm.keyExistsJson(json, ".contracts.faucet")) {
                address faucetAddr = vm.parseJsonAddress(json, ".contracts.faucet");
                console.log("Faucet already deployed at:", faucetAddr);
                faucet = Faucet(faucetAddr);
            }
            if (vm.keyExistsJson(json, ".contracts.marketViewer")) {
                address marketViewerAddr = vm.parseJsonAddress(json, ".contracts.marketViewer");
                console.log("MarketViewer already deployed at:", marketViewerAddr);
                marketViewer = MarketViewer(marketViewerAddr);
            }
        }
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        IWhitelistManager whitelistManager = deployWhitelistManager(accessManagerAddr);

        if (
            keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("eth-mainnet"))
                || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))
                || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("bnb-mainnet"))
        ) {
            if (address(router) == address(0)) {
                (
                    factory,
                    vaultFactory,
                    priceFeedFactory,
                    router,
                    makerHelper,
                    marketViewer,
                    uniswapV3Adapter,
                    odosV2Adapter,
                    pendleSwapV3Adapter,
                    vaultAdapter,
                    termMaxSwapAdapter
                ) = deployCoreMainnet(
                    accessManagerAddr,
                    address(whitelistManager),
                    uniswapV3RouterAddr,
                    odosV2RouterAddr,
                    pendleSwapV3RouterAddr
                );
            } else {
                (
                    factory,
                    vaultFactory,
                    priceFeedFactory,
                    router,
                    makerHelper,
                    uniswapV3Adapter,
                    odosV2Adapter,
                    pendleSwapV3Adapter,
                    vaultAdapter,
                    termMaxSwapAdapter
                ) = deployAndUpgradeCoreMainnet(
                    accessManagerAddr,
                    address(whitelistManager),
                    address(router),
                    uniswapV3RouterAddr,
                    odosV2RouterAddr,
                    pendleSwapV3RouterAddr
                );
            }
        } else {
            if (address(router) == address(0)) {
                (factory, vaultFactory, priceFeedFactory, router, makerHelper, swapAdapter, faucet, marketViewer) =
                    deployCore(deployerAddr, accessManagerAddr);
            } else {
                (factory, vaultFactory, priceFeedFactory, router, makerHelper, swapAdapter) =
                    deployAndUpgradeCore(deployerAddr, accessManagerAddr, address(router));
            }
        }
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))) {
            // Deploy OracleAggregator with L2 sequencer feed
            oracleAggregator = deployOracleAggregatorWithSequencer(
                accessManagerAddr, oracleTimelock, l2SequencerUptimeFeed, l2SequencerGracePeriod
            );
        } else {
            // Deploy default OracleAggregator without L2 sequencer feed
            oracleAggregator = deployOracleAggregator(accessManagerAddr, oracleTimelock);
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
        console.log("Deployer:", deployerAddr);
        console.log("Admin:", adminAddr);
        console.log("FactoryV2 deployed at:", address(factory));
        console.log("VaultFactoryV2 deployed at:", address(vaultFactory));
        console.log("PriceFeedFactoryV2 deployed at:", address(priceFeedFactory));
        console.log("Oracle AggregatorV2 deployed at:", address(oracleAggregator));
        console.log("RouterV2 deployed at:", address(router));
        console.log("Maker helper deployed at:", address(makerHelper));
        if (
            keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("eth-mainnet"))
                && keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("arb-mainnet"))
        ) {
            console.log("SwapAdapterV2 deployed at:", address(swapAdapter));
            console.log("Faucet deployed at:", address(faucet));
        }
        console.log("MarketViewer deployed at:", address(marketViewer));
        console.log();

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
                    vm.toString(deployerAddr),
                    '",\n',
                    '  "admin": "',
                    vm.toString(adminAddr),
                    '",\n',
                    '  "contracts": {\n',
                    '    "factoryV2": "',
                    vm.toString(address(factory)),
                    '",\n',
                    '    "vaultFactoryV2": "',
                    vm.toString(address(vaultFactory)),
                    '",\n',
                    '    "priceFeedFactoryV2": "',
                    vm.toString(address(priceFeedFactory)),
                    '",\n',
                    '    "oracleAggregatorV2": "',
                    vm.toString(address(oracleAggregator)),
                    '",\n',
                    '    "routerV2": "',
                    vm.toString(address(router)),
                    '",\n',
                    '    "makerHelper": "',
                    vm.toString(address(makerHelper)),
                    '",\n',
                    '    "swapAdapterV2": '
                )
            );
        }

        {
            deploymentJson = string(
                abi.encodePacked(
                    deploymentJson,
                    keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("eth-mainnet"))
                        || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))
                        || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("bnb-mainnet"))
                        ? string.concat(
                            "{\n",
                            '      "uniswapV3AdapterV2": "',
                            vm.toString(address(uniswapV3Adapter)),
                            '",\n',
                            '      "odosV2AdapterV2": "',
                            vm.toString(address(odosV2Adapter)),
                            '",\n',
                            '      "pendleSwapV3AdapterV2": "',
                            vm.toString(address(pendleSwapV3Adapter)),
                            '",\n',
                            '      "ERC4626VaultAdapterV2": "',
                            vm.toString(address(vaultAdapter)),
                            '",\n',
                            '      "TermMaxSwapAdapter": "',
                            vm.toString(address(termMaxSwapAdapter)),
                            '"\n',
                            "    },\n"
                        )
                        : string.concat('"', vm.toString(address(swapAdapter)), '",\n'),
                    keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("eth-mainnet"))
                        && keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("arb-mainnet"))
                        && keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("bnb-mainnet"))
                        ? string.concat('    "faucet": "', vm.toString(address(faucet)), '",\n')
                        : "",
                    '    "marketViewer": "',
                    vm.toString(address(marketViewer)),
                    '"\n',
                    "  }\n",
                    "}"
                )
            );
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core-v2.json");

        vm.writeFile(deploymentPath, deploymentJson);
        console.log("Deployment info written to:", deploymentPath);
    }
}
