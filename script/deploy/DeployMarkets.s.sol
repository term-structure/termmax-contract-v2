// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OrderConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {JsonLoader} from "script/utils/JsonLoader.sol";
import {OrderV2ConfigurationParams} from "contracts/v2/vault/VaultStorageV2.sol";
import {ITermMaxOrderV2} from "contracts/v2/ITermMaxOrderV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";

contract DeployMarketsScript is DeployBaseV2 {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;
    address treasurerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address[] markets;
    string configPath = "script/deploy/deploydata/eth-mainnet-markets.json";

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        // Load network-specific configuration
        {
            string memory networkUpper = toUpper(network);
            string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
            string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

            deployerPrivateKey = vm.envUint(privateKeyVar);
            adminAddr = vm.envAddress(adminVar);
            deployerAddr = vm.addr(deployerPrivateKey);
            treasurerAddr = vm.envAddress(string.concat(networkUpper, "_TREASURER_ADDRESS"));

            console.log("Admin:", adminAddr);
            console.log("Deployer:", deployerAddr);
            console.log("Treasurer:", treasurerAddr);
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        coreContracts.accessManager = AccessManagerV2(vm.parseJsonAddress(json, ".contracts.accessManager"));

        deploymentPath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core-v2.json");

        json = vm.readFile(deploymentPath);

        coreContracts.whitelistManager = WhitelistManager(vm.parseJsonAddress(json, ".contracts.whitelistManager"));
        console.log("Whitelist Manager already deployed at:", address(coreContracts.whitelistManager));

        coreContracts.router = TermMaxRouterV2(vm.parseJsonAddress(json, ".contracts.routerV2"));
        console.log("Router V2 already deployed at:", address(coreContracts.router));

        coreContracts.factory = TermMaxFactoryV2(vm.parseJsonAddress(json, ".contracts.factoryV2"));
        console.log("Market Factory V2 already deployed at:", address(coreContracts.factory));

        coreContracts.priceFeedFactory =
            TermMaxPriceFeedFactoryV2(vm.parseJsonAddress(json, ".contracts.priceFeedFactoryV2"));
        console.log("Price Feed Factory already deployed at:", address(coreContracts.priceFeedFactory));

        coreContracts.oracle = IOracle(vm.parseJsonAddress(json, ".contracts.oracleAggregatorV2"));
        if (address(coreContracts.oracle) == address(0)) {
            revert("Oracle not deployed");
        }
        console.log("Oracle already deployed at:", address(coreContracts.oracle));
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        {
            JsonLoader.Config[] memory configs = JsonLoader.getConfigsFromJson(vm.readFile(configPath));
            for (uint256 i; i < configs.length; i++) {
                JsonLoader.Config memory config = configs[i];
                console.log("Processing config:", i);
                console.log("  Market Name:", config.marketName);
                console.log("  Market Symbol:", config.marketSymbol);
                console.log("  Salt:", config.salt);
                console.log("  Collateral Cap For GT:", config.collateralCapForGt);
                console.log("  Market Maturity:", config.marketConfig.maturity);
                console.log("  Underlying Token Address:", config.underlyingConfig.tokenAddr);
                console.log("  Collateral Token Address:", config.collateralConfig.tokenAddr);

                config.loanConfig.oracle = coreContracts.oracle;
                config.marketConfig.treasurer = treasurerAddr;
                // deploy new market
                MarketInitialParams memory params = MarketInitialParams({
                    collateral: config.collateralConfig.tokenAddr,
                    debtToken: IERC20Metadata(config.underlyingConfig.tokenAddr),
                    admin: address(coreContracts.accessManager),
                    gtImplementation: address(0),
                    marketConfig: config.marketConfig,
                    loanConfig: config.loanConfig,
                    gtInitalParams: abi.encode(config.collateralCapForGt),
                    tokenName: config.marketName,
                    tokenSymbol: config.marketSymbol
                });
                address market = coreContracts.accessManager.createMarket(
                    coreContracts.factory,
                    keccak256(bytes(config.collateralConfig.gtKeyIdentifier)),
                    params,
                    config.salt
                );
                console.log("  Market deployed at:", market);
                markets.push(market);
            }
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

        string memory deploymentEnv = string(
            abi.encodePacked(
                "NETWORK=",
                network,
                "\nDEPLOYED_AT=",
                vm.toString(block.timestamp),
                "\nGIT_BRANCH=",
                getGitBranch(),
                "\nGIT_COMMIT_HASH=0x",
                vm.toString(getGitCommitHash()),
                "\nBLOCK_NUMBER=",
                vm.toString(block.number),
                "\nBLOCK_TIMESTAMP=",
                vm.toString(block.timestamp),
                "\nDEPLOYER_ADDRESS=",
                vm.toString(deployerAddr),
                "\nADMIN_ADDRESS=",
                vm.toString(adminAddr)
            )
        );
        for (uint256 i = 3; i < markets.length; i++) {
            deploymentEnv = string(
                abi.encodePacked(
                    deploymentEnv, "MARKET_ADDRESS_", vm.toString(i + 1), "=", vm.toString(markets[i]), "\n"
                )
            );
        }

        string memory path = string.concat(
            vm.projectRoot(),
            "/deployments/",
            network,
            "/",
            network,
            "-v2-markets-",
            vm.toString(block.timestamp),
            ".env"
        );
        vm.writeFile(path, deploymentEnv);
    }
}
