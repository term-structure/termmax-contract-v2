// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {MarketViewer} from "contracts/router/MarketViewer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";
import {DeployBase} from "../DeployBase.s.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";

contract DeployCoreArbSepolia is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");

    function run() public {
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

        console.log("===== Core Info =====");
        console.log("Deplyer:", deployerAddr);
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
                '  "network": "arb-sepolia",\n',
                '  "deployedAt": "',
                vm.toString(block.timestamp),
                '",\n',
                '  "gitBranch": "',
                getGitBranch(),
                '",\n',
                '  "gitCommitHash": "0x',
                vm.toString(getGitCommitHash()),
                '",\n',
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
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/arb-sepolia");
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

        string memory deploymentPath = string.concat(deploymentsDir, "/arb-sepolia-core.json");
        vm.writeFile(deploymentPath, deploymentJson);
        console.log("Deployment info written to:", deploymentPath);
    }
}
