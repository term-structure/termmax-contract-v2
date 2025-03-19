// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {MarketViewer} from "contracts/router/MarketViewer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";

contract DeployCore is DeployBase {
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
        console.log("Deployer balance:", deployerAddr.balance);

        uint256 currentBlock = block.number;
        uint256 currentTimestamp = block.timestamp;

        vm.startBroadcast(deployerPrivateKey);
        (
            ITermMaxFactory factory,
            IVaultFactory vaultFactory,
            IOracle oracleAggregator,
            ITermMaxRouter router,
            SwapAdapter swapAdapter,
            Faucet faucet
        ) = deployCore(adminAddr);
        MarketViewer marketViewer = deployMarketViewer();
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

        console.log("===== Core Info =====");
        console.log("Deployer:", deployerAddr);
        console.log("Admin:", adminAddr);
        console.log("Factory deployed at:", address(factory));
        console.log("VaultFactory deployed at:", address(vaultFactory));
        console.log("Oracle Aggregator deployed at:", address(oracleAggregator));
        console.log("Router deployed at:", address(router));
        console.log("SwapAdapter deployed at:", address(swapAdapter));
        console.log("Faucet deployed at:", address(faucet));
        console.log("MarketViewer deployed at:", address(marketViewer));
        console.log();

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
                '    "factory": "',
                vm.toString(address(factory)),
                '",\n',
                '    "vaultFactory": "',
                vm.toString(address(vaultFactory)),
                '",\n',
                '    "oracleAggregator": "',
                vm.toString(address(oracleAggregator)),
                '",\n',
                '    "router": "',
                vm.toString(address(router)),
                '",\n',
                '    "swapAdapter": "',
                vm.toString(address(swapAdapter)),
                '",\n',
                '    "faucet": "',
                vm.toString(address(faucet)),
                '",\n',
                '    "marketViewer": "',
                vm.toString(address(marketViewer)),
                '"\n',
                "  }\n",
                "}"
            )
        );

        // Create deployments directory if it doesn't exist
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (vm.exists(deploymentsDir)) {
            // Directory exists, clean it by removing all files
            VmSafe.DirEntry[] memory files = vm.readDir(deploymentsDir);
            for (uint256 i = 0; i < files.length; i++) {
                vm.removeFile(files[i].path);
            }
        } else {
            // Directory doesn't exist, create it
            vm.createDir(deploymentsDir, true);
        }

        string memory deploymentPath = string.concat(deploymentsDir, "/", network, "-core.json");
        vm.writeFile(deploymentPath, deploymentJson);
        console.log("Deployment info written to:", deploymentPath);
    }
}
