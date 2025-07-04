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
import {KyberswapV2Adapter} from "contracts/v1/router/swapAdapters/KyberswapV2Adapter.sol";
import {OdosV2Adapter} from "contracts/v1/router/swapAdapters/OdosV2Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/v1/router/swapAdapters/PendleSwapV3Adapter.sol";
import {UniswapV3Adapter} from "contracts/v1/router/swapAdapters/UniswapV3Adapter.sol";
import {ERC4626VaultAdapter} from "contracts/v1/router/swapAdapters/ERC4626VaultAdapter.sol";
import {AccessManager} from "contracts/v1/access/AccessManager.sol";

contract DeployCore is DeployBase {
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

    AccessManager accessManager;
    ITermMaxFactory factory;
    IVaultFactory vaultFactory;
    IOracle oracleAggregator;
    ITermMaxRouter router;
    MarketViewer marketViewer;
    UniswapV3Adapter uniswapV3Adapter;
    OdosV2Adapter odosV2Adapter;
    PendleSwapV3Adapter pendleSwapV3Adapter;
    ERC4626VaultAdapter vaultAdapter;
    SwapAdapter swapAdapter;
    Faucet faucet;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");
        string memory oracleTimelockVar = string.concat(networkUpper, "_ORACLE_TIMELOCK");

        oracleTimelock = vm.envUint(oracleTimelockVar);
        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);

        uint256 currentBlock = block.number;
        uint256 currentTimestamp = block.timestamp;

        vm.startBroadcast(deployerPrivateKey);
        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(accessManagerAddr, oracleTimelock);
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

        console.log("===== Oracle Aggregator Info =====");
        console.log("Deployer:", deployerAddr);
        console.log("Admin:", adminAddr);
        console.log("Oracle Aggregator deployed at:", address(oracleAggregator));
        console.log("Oracle Timelock:", oracleTimelock);
    }
}
