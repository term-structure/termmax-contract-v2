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

    struct AavePools {
        address assets;
        address variable;
        address stable;
    }

    AavePools[] public aavePools;

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
            coreContracts = readDeployData(vm.readFile(deploymentPath));
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

        if (coreContracts.whitelistManager == WhitelistManager(address(0))) {
            coreContracts.whitelistManager = deployWhitelistManager(address(coreContracts.accessManager));
            console.log("WhitelistManager deployed at:", address(coreContracts.whitelistManager));
            coreContracts.accessManager.grantRole(coreContracts.accessManager.WHITELIST_ROLE(), coreParams.deployerAddr);
        } else {
            console.log("Using existing WhitelistManager at:", address(coreContracts.whitelistManager));
        }
        coreContracts.tmx4626Factory = new TermMax4626Factory(coreParams.AAVE_POOL, coreParams.AAVE_REFERRAL_CODE);
        console.log("TermMax4626Factory deployed at:", address(coreContracts.tmx4626Factory));

        string memory configPath =
            string.concat(vm.projectRoot(), "/script/deploy/deploydata/", coreParams.network, "-aave-pool.json");
        JsonLoader.PoolConfig[] memory poolConfigs = JsonLoader.getPoolConfigsFromJson(vm.readFile(configPath));
        address[] memory thirdPools = new address[](poolConfigs.length * 2);
        for (uint256 i = 0; i < poolConfigs.length; i++) {
            console.log("Deploying AavePool for asset:", poolConfigs[i].asset);
            (VariableERC4626ForAave aaveVariable, StableERC4626ForAave aaveStable) = coreContracts
                .tmx4626Factory
                .createVariableAndStableERC4626ForAave(
                coreParams.adminAddr, poolConfigs[i].asset, poolConfigs[i].bufferConfig
            );
            aavePools.push(
                AavePools({assets: poolConfigs[i].asset, variable: address(aaveVariable), stable: address(aaveStable)})
            );
            console.log("  Deployed VariableERC4626ForAave at:", address(aaveVariable));
            console.log("  Deployed StableERC4626ForAave at:", address(aaveStable));
            thirdPools[i * 2] = address(aaveVariable);
            thirdPools[i * 2 + 1] = address(aaveStable);
        }

        // whitelist the pool
        coreContracts.accessManager.batchSetWhitelist(
            coreContracts.whitelistManager, thirdPools, IWhitelistManager.ContractModule.POOL, true
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
        console.log("Admin:", coreParams.adminAddr);

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );

        writeAsJson(deploymentPath, coreParams, coreContracts);
    }

    function writeToEnv() internal {
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
                vm.toString(coreParams.adminAddr)
            )
        );
        for (uint256 i = 0; i < aavePools.length; i++) {
            deploymentEnv = string(
                abi.encodePacked(
                    deploymentEnv,
                    "ASSET_ADDRESS_",
                    vm.toString(i + 1),
                    "=",
                    vm.toString(aavePools[i].assets),
                    "\n",
                    "STABLE_AAVE_POOL_ADDRESS_",
                    vm.toString(i + 1),
                    "=",
                    vm.toString(aavePools[i].stable),
                    "\n",
                    "VARIABLE_AAVE_POOL_ADDRESS_",
                    vm.toString(i + 1),
                    "=",
                    vm.toString(aavePools[i].variable),
                    "\n"
                )
            );
        }

        string memory path = string.concat(
            vm.projectRoot(),
            "/deployments/",
            coreParams.network,
            "/",
            coreParams.network,
            "-v2-aave-pools-",
            vm.toString(block.timestamp),
            ".env"
        );
        vm.writeFile(path, deploymentEnv);
    }
}
