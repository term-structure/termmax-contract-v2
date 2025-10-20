// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {TermMaxPancakeTWAPPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxPancakeTWAPPriceFeed.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployOracle is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    string oracleEnvs;

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
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        address pancakeFactory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
        address baseToken;
        address quoteToken;
        uint32 _twapPeriod = 900;
        uint24 fee = 500;
        address pool = IUniswapV3Factory(pancakeFactory).getPool(baseToken, quoteToken, fee);
        require(pool != address(0), "Pool doesn't exist");
        TermMaxPancakeTWAPPriceFeed priceFeed =
            new TermMaxPancakeTWAPPriceFeed(pool, _twapPeriod, baseToken, quoteToken);
        console.log("Deployed TermMaxPancakeTWAPPriceFeed at:", address(priceFeed));

        oracleEnvs = string.concat(
            "BASE_TOKEN=",
            toUpper(vm.toString(baseToken)),
            "\nQUOTE_TOKEN=",
            toUpper(vm.toString(quoteToken)),
            "\nPRICE_FEED_ADDRESS=",
            vm.toString(address(priceFeed))
        );
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
