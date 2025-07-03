// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/v1/TermMaxMarket.sol";
import {TermMaxOrder, ISwapCallback} from "contracts/v1/TermMaxOrder.sol";
import {ITermMaxOrder} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MarketConfig, OrderConfig, CurveCuts, CurveCut} from "contracts/v1/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "contracts/v1/test/MockSwapAdapter.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {FaucetERC20} from "contracts/v1/test/testnet/FaucetERC20.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {AccessManager} from "contracts/v1/access/AccessManager.sol";

contract DeloyVault is DeployBase {
    // Initialize vault configurations with a single USDC vault
    address assetAddr = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address curator = address(0x2A58A3D405c527491Daae4C62561B949e7F87EFE);
    address guardian = address(0x2A58A3D405c527491Daae4C62561B949e7F87EFE);
    address allocator = address(0x2A58A3D405c527491Daae4C62561B949e7F87EFE);
    string name = "TermMax USDC Prime";
    string symbol = "TMX-USDC-PRIME";
    uint256 timelock = 1 days;
    uint256 maxCapacity = 50000000e6;
    uint64 performanceFeeRate = 0;

    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address accessManagerAddr;

    address vaultFactoryAddr;

    struct VaultConfig {
        address assetAddr;
        string name;
        string symbol;
        address curator;
        address guardian;
        address allocator;
        uint256 timelock;
        uint256 maxCapacity;
        uint64 performanceFeeRate;
    }
    // address config

    string coreContractPath;
    VaultConfig vaultConfig;

    function setUp() public {
        vaultConfig = VaultConfig({
            assetAddr: assetAddr,
            name: name,
            symbol: symbol,
            curator: curator,
            guardian: guardian,
            allocator: allocator,
            timelock: timelock,
            maxCapacity: maxCapacity,
            performanceFeeRate: performanceFeeRate
        });

        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory accessManagerPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(accessManagerPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");
        coreContractPath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        string memory networkUpper = toUpper(network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");

        deployerPrivateKey = vm.envUint(privateKeyVar);

        json = vm.readFile(coreContractPath);
        vaultFactoryAddr = vm.parseJsonAddress(json, ".contracts.vaultFactory");
    }

    function run() public {
        uint256 currentBlockNum = block.number;
        uint256 currentTimestamp = block.timestamp;

        vm.startBroadcast(deployerPrivateKey);
        ITermMaxVault vault = deployVault(
            vaultFactoryAddr,
            accessManagerAddr,
            vaultConfig.curator,
            vaultConfig.timelock,
            vaultConfig.assetAddr,
            vaultConfig.maxCapacity,
            vaultConfig.name,
            vaultConfig.symbol,
            vaultConfig.performanceFeeRate
        );

        AccessManager accessManager = AccessManager(accessManagerAddr);
        accessManager.submitVaultGuardian(vault, vaultConfig.guardian);
        accessManager.setIsAllocatorForVault(vault, vaultConfig.allocator, true);

        writeDeploymentJson(currentBlockNum, currentTimestamp, vault, vaultConfig);

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Vault Info =====");
        console.log("Vault", vaultConfig.name, ":", address(vault));
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");
    }

    function writeDeploymentJson(
        uint256 currentBlockNum,
        uint256 currentTimestamp,
        ITermMaxVault vault,
        VaultConfig memory config
    ) public {
        // Write individual vault info to JSON
        string memory vaultPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-vault-", vault.symbol(), ".json");

        string memory vaultJson = generateVaultJson(currentBlockNum, currentTimestamp, vault, config);

        vm.writeFile(vaultPath, vaultJson);
        console.log("Vault info written to:", vaultPath);
    }

    function generateVaultJson(
        uint256 currentBlockNum,
        uint256 currentTimestamp,
        ITermMaxVault vault,
        VaultConfig memory config
    ) internal returns (string memory) {
        string memory part1 = generateVaultJsonPart1(currentBlockNum, currentTimestamp);
        string memory part2 = generateVaultJsonPart2(vault, config);
        return string.concat(part1, part2);
    }

    function generateVaultJsonPart1(uint256 currentBlockNum, uint256 currentTimestamp)
        internal
        returns (string memory)
    {
        return string.concat(
            "{\n",
            '  "gitInfo": {\n',
            '    "branch": "',
            getGitBranch(),
            '",\n',
            '    "commit": "0x',
            vm.toString(getGitCommitHash()),
            '"\n',
            "  },\n",
            '  "blockInfo": {\n',
            '    "network": "',
            network,
            '",\n',
            '    "blockNumber": "',
            vm.toString(currentBlockNum),
            '",\n',
            '    "timestamp": "',
            vm.toString(currentTimestamp),
            '"\n',
            "  },\n"
        );
    }

    function generateVaultJsonPart2(ITermMaxVault vault, VaultConfig memory config)
        internal
        view
        returns (string memory)
    {
        return string.concat(
            '  "vaultInfo": {\n',
            '    "name": "',
            config.name,
            '",\n',
            '    "symbol": "',
            config.symbol,
            '",\n',
            '    "address": "',
            vm.toString(address(vault)),
            '",\n',
            '    "asset": "',
            vm.toString(config.assetAddr),
            '",\n',
            '    "performanceFeeRate": ',
            vm.toString(config.performanceFeeRate),
            ",\n",
            '    "maxCapacity": "',
            vm.toString(config.maxCapacity),
            '",\n',
            '    "timelock": ',
            vm.toString(config.timelock),
            ",\n",
            '    "admin": "',
            vm.toString(accessManagerAddr),
            '",\n',
            '    "curator": "',
            vm.toString(config.curator),
            '",\n',
            '    "guardian": "',
            vm.toString(config.guardian),
            '",\n',
            '    "allocator": "',
            vm.toString(config.allocator),
            '"\n',
            "  }\n",
            "}"
        );
    }
}
