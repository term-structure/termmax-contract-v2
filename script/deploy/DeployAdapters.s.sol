// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {MarketViewer} from "contracts/v1/router/MarketViewer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/v1/TermMaxMarket.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "contracts/v1/test/testnet/SwapAdapter.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {AccessManager} from "contracts/v1/access/AccessManager.sol";
import {UniswapV3AdapterV2} from "contracts/v1/router/specAdapters/UniswapV3AdapterV2.sol";
import {OdosV2AdapterV2} from "contracts/v1/router/specAdapters/OdosV2AdapterV2.sol";
import {PendleSwapV3AdapterV2} from "contracts/v1/router/specAdapters/PendleSwapV3AdapterV2.sol";
import {ERC4626VaultAdapterV2} from "contracts/v1/router/specAdapters/ERC4626VaultAdapterV2.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract DeployAdapters is DeployBase {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;
    address accessManagerAddr;
    address uniswapV3RouterAddr;
    address odosV2RouterAddr;
    address pendleSwapV3RouterAddr;
    address routerAddr;

    AccessManager accessManager;
    ITermMaxRouter router;
    UniswapV3AdapterV2 uniswapV3Adapter;
    OdosV2AdapterV2 odosV2Adapter;
    PendleSwapV3AdapterV2 pendleSwapV3Adapter;
    ERC4626VaultAdapterV2 vaultAdapter;

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
            uniswapV3RouterAddr = vm.envAddress(uniswapV3RouterVar);
            odosV2RouterAddr = vm.envAddress(odosV2RouterVar);
            pendleSwapV3RouterAddr = vm.envAddress(pendleSwapV3RouterVar);
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        deploymentPath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        json = vm.readFile(deploymentPath);
        routerAddr = vm.parseJsonAddress(json, ".contracts.router");
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());

        uint256 currentBlock = block.number;
        uint256 currentTimestamp = block.timestamp;

        vm.startBroadcast(deployerPrivateKey);
        // if (
        //     keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("eth-mainnet"))
        //         || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))
        //         || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("bnb-mainnet"))
        // ) {
        (uniswapV3Adapter, odosV2Adapter, pendleSwapV3Adapter, vaultAdapter) =
            deployAdapters(accessManagerAddr, routerAddr, uniswapV3RouterAddr, odosV2RouterAddr, pendleSwapV3RouterAddr);
        // } else {
        //     revert("This script is only for mainnet deployments");
        // }
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", currentBlock);
        console.log("Block timestamp:", currentTimestamp);
        console.log();

        console.log("===== Core Info =====");
        console.log("Use access manager:", accessManagerAddr);
        console.log("Use router:", routerAddr);

        // Write deployment results to a JSON file with timestamp
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
                '  "gitCommitHash": "',
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
                '  "swapAdapter": ',
                string.concat(
                    "{\n",
                    '    "uniswapV3Adapter": "',
                    vm.toString(address(uniswapV3Adapter)),
                    '",\n',
                    '    "odosV2Adapter": "',
                    vm.toString(address(odosV2Adapter)),
                    '",\n',
                    '    "pendleSwapV3Adapter": "',
                    vm.toString(address(pendleSwapV3Adapter)),
                    '",\n',
                    '    "ERC4626VaultAdapter": "',
                    vm.toString(address(vaultAdapter)),
                    '"\n',
                    "  }\n"
                ),
                "}"
            )
        );

        // Create deployments directory if it doesn't exist
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            // Directory doesn't exist, create it
            vm.createDir(deploymentsDir, true);
        }

        // Create filename with date string using StringHelper
        string memory dateString = getDateSuffix();
        string memory deploymentPath = string.concat(deploymentsDir, "/", network, "-adapters-", dateString, ".json");
        vm.writeFile(deploymentPath, deploymentJson);
        console.log("Deployment info written to:", deploymentPath);
    }
}
