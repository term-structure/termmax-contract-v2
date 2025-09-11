// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployMakerHelper is DeployBaseV2 {
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

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");
        accessManager = AccessManagerV2(accessManagerAddr);
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("Access manager address:", accessManagerAddr);

        vm.startBroadcast(deployerPrivateKey);
        makerHelper = deployMakerHelper(address(accessManager));
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
        console.log("Maker helper deployed at:", address(makerHelper));

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
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-maker-helper.json");

        vm.writeFile(deploymentPath, deploymentJson);
        console.log("Deployment info written to:", deploymentPath);
    }
}
