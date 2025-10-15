// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployOracle is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    string oracleEnvs;
    string configPath = "-pricefeeds.json";

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(coreParams.network);
        configPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", coreParams.network, configPath);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

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

        string memory deploymentPath = string.concat(
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
        console.log("Using existing OracleAggregatorV2 at:", address(coreContracts.oracle));
        console.log("Using existing TermMaxPriceFeedFactoryV2 at:", address(coreContracts.priceFeedFactory));
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        JsonLoader.OracleConfig[] memory oracleConfigs = JsonLoader.getOracleConfigsFromJson(vm.readFile(configPath));
        for (uint256 i; i < oracleConfigs.length; i++) {
            JsonLoader.OracleConfig memory config = oracleConfigs[i];
            console.log("Setting oracle for asset index:", i);
            console.log("  Asset:", config.asset);
            console.log("  Need to deploy price feed:", config.needsDeployment);
            if (config.needsDeployment) {
                if (config.deployFeedParams.priceFeedType == JsonLoader.PriceFeedType.PriceFeedWithERC4626) {
                    config.oracleParams.aggregator = AggregatorV3Interface(
                        coreContracts.priceFeedFactory.createPriceFeedWithERC4626(
                            config.deployFeedParams.underlyingPriceFeed, config.asset
                        )
                    );
                    config.oracleParams.aggregator = AggregatorV3Interface(vm.randomAddress());
                    console.log("  Deployed ERC4626 price feed at:", address(config.oracleParams.aggregator));
                } else if (config.deployFeedParams.priceFeedType == JsonLoader.PriceFeedType.PriceFeedConverter) {
                    config.oracleParams.aggregator = AggregatorV3Interface(
                        coreContracts.priceFeedFactory.createPriceFeedConverter(
                            config.deployFeedParams.priceFeed1, config.deployFeedParams.priceFeed2, config.asset
                        )
                    );
                    config.oracleParams.aggregator = AggregatorV3Interface(vm.randomAddress());
                    console.log("  Deployed price feed converter at:", address(config.oracleParams.aggregator));
                } else if (config.deployFeedParams.priceFeedType == JsonLoader.PriceFeedType.PTWithPriceFeed) {
                    config.oracleParams.aggregator = AggregatorV3Interface(
                        coreContracts.priceFeedFactory.createPTWithPriceFeed(
                            config.deployFeedParams.pendlePYLpOracle,
                            config.deployFeedParams.market,
                            config.deployFeedParams.duration,
                            config.deployFeedParams.underlyingPriceFeed
                        )
                    );
                    config.oracleParams.aggregator = AggregatorV3Interface(vm.randomAddress());
                    console.log("  Deployed PT price feed at:", address(config.oracleParams.aggregator));
                } else if (config.deployFeedParams.priceFeedType == JsonLoader.PriceFeedType.ConstantPriceFeed) {
                    config.oracleParams.aggregator = AggregatorV3Interface(
                        coreContracts.priceFeedFactory.createConstantPriceFeed(config.deployFeedParams.constantPrice)
                    );
                    config.oracleParams.aggregator = AggregatorV3Interface(vm.randomAddress());
                    console.log("  Deployed constant price feed at:", address(config.oracleParams.aggregator));
                }
            } else {
                console.log("  Using existing primary aggregator at:", address(config.oracleParams.aggregator));
            }
            console.log("  heartBeat:", config.oracleParams.heartbeat);
            if (address(config.oracleParams.backupAggregator) != address(0)) {
                console.log("  Using existing backup aggregator at:", address(config.oracleParams.backupAggregator));
                console.log("  backupHeartBeat:", config.oracleParams.backupHeartbeat);
            }
            console.log("  minPrice:", config.oracleParams.minPrice);
            console.log("  maxPrice:", config.oracleParams.maxPrice);

            oracleEnvs = string.concat(
                oracleEnvs,
                "_ASSET_=",
                vm.toString(i + 1),
                vm.toString(config.asset),
                "\nAGGREGATOR=",
                vm.toString(address(config.oracleParams.aggregator)),
                "\nBACKUP_AGGREGATOR=",
                vm.toString(address(config.oracleParams.backupAggregator)),
                "\n"
            );
            IOracle.Oracle memory oracleParams = IOracle.Oracle({
                aggregator: config.oracleParams.aggregator,
                heartbeat: config.oracleParams.heartbeat,
                backupAggregator: config.oracleParams.backupAggregator
            });
            // submit to oracle aggregator v1
            coreContracts.accessManager.submitPendingOracle(coreContracts.oracle, config.asset, oracleParams);
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
        console.log("Deployer:", coreParams.deployerAddr);
        console.log("Admin:", adminAddr);

        string memory deploymentEnv = string(
            abi.encodePacked(
                "NETWORK=",
                coreParams.network,
                "\nDEPLOYED_AT=",
                vm.toString(block.timestamp),
                "\nGIT_BRANCH=",
                getGitBranch(),
                "\nGIT_COMMIT_HASH=",
                vm.toString(getGitCommitHash()),
                "\nBLOCK_NUMBER=",
                vm.toString(block.number),
                "\nBLOCK_TIMESTAMP=",
                vm.toString(block.timestamp),
                "\nDEPLOYER_ADDRESS=",
                vm.toString(vm.addr(deployerPrivateKey)),
                "\nADMIN_ADDRESS=",
                vm.toString(adminAddr)
            )
        );
        deploymentEnv = string(abi.encodePacked(deploymentEnv, "\n", oracleEnvs));

        string memory path = string.concat(
            vm.projectRoot(),
            "/deployments/",
            coreParams.network,
            "/",
            coreParams.network,
            "-v2-oracles-",
            vm.toString(block.timestamp),
            ".env"
        );
        vm.writeFile(path, deploymentEnv);
    }
}
