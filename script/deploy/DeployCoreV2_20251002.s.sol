// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployCoreV2_20251002 is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");
        {
            string memory AAVEPoolVar = string.concat(networkUpper, "_AAVE_POOL");
            string memory AAVEReferralCodeVar = string.concat(networkUpper, "_AAVE_REFERRAL_CODE");
            coreParams.AAVE_POOL = vm.envAddress(AAVEPoolVar);
            coreParams.AAVE_REFERRAL_CODE = uint16(vm.envUint(AAVEReferralCodeVar));
        }

        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        coreParams.adminAddr = vm.envAddress(adminVar);

        coreParams.isMainnet = keccak256(abi.encodePacked(coreParams.network))
            == keccak256(abi.encodePacked("eth-mainnet"))
            || keccak256(abi.encodePacked(coreParams.network)) == keccak256(abi.encodePacked("arb-mainnet"))
            || keccak256(abi.encodePacked(coreParams.network)) == keccak256(abi.encodePacked("bnb-mainnet"));
        coreParams.isL2Network = (
            keccak256(abi.encodePacked(toUpper(coreParams.network))) == keccak256(abi.encodePacked("arb-mainnet"))
        ) || (keccak256(abi.encodePacked(toUpper(coreParams.network))) == keccak256(abi.encodePacked("arb-sepolia")));
        if (coreParams.isMainnet) {
            string memory uniswapV3RouterVar = string.concat(networkUpper, "_UNISWAP_V3_ROUTER_ADDRESS");
            string memory odosV2RouterVar = string.concat(networkUpper, "_ODOS_V2_ROUTER_ADDRESS");
            string memory pendleSwapV3RouterVar = string.concat(networkUpper, "_PENDLE_SWAP_V3_ROUTER_ADDRESS");
            string memory oracleTimelockVar = string.concat(networkUpper, "_ORACLE_TIMELOCK");
            coreParams.uniswapV3Router = vm.envAddress(uniswapV3RouterVar);
            coreParams.odosV2Router = vm.envAddress(odosV2RouterVar);
            coreParams.pendleSwapV3Router = vm.envAddress(pendleSwapV3RouterVar);
            coreParams.oracleTimelock = vm.envUint(oracleTimelockVar);
        }
        if (coreParams.isL2Network) {
            string memory l2SequencerUptimeFeedVar = string.concat(networkUpper, "_L2_SEQUENCER_UPTIME_FEED");
            coreParams.l2SequencerUpPriceFeed = vm.envAddress(l2SequencerUptimeFeedVar);
            string memory l2SequencerGracePeriodVar = string.concat(networkUpper, "_L2_SEQUENCER_GRACE_PERIOD");
            coreParams.l2GracePeriod = vm.envUint(l2SequencerGracePeriodVar);
        }
        {
            // Create deployments directory if it doesn't exist
            string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", coreParams.network);
            if (!vm.exists(deploymentsDir)) {
                // Directory doesn't exist, create it
                vm.createDir(deploymentsDir, true);
            }
        }

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );
        if (vm.exists(deploymentPath)) {
            string memory json = vm.readFile(deploymentPath);
            coreContracts = readDeployData(json);
        }

        deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-access-manager.json"
        );
        string memory json = vm.readFile(deploymentPath);

        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");
        console.log("Using existing AccessManagerV2 at:", accessManagerAddr);
        coreContracts.accessManager = AccessManagerV2(accessManagerAddr);
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        coreContracts.factory = deployFactory(address(coreContracts.accessManager));
        console.log("FactoryV2 deployed at:", address(coreContracts.factory));

        coreContracts.vaultFactory = deployVaultFactory();
        console.log("VaultFactoryV2 deployed at:", address(coreContracts.vaultFactory));

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
        console.log("Admin:", coreParams.adminAddr);

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );

        writeAsJson(deploymentPath, coreParams, coreContracts);
    }
}
