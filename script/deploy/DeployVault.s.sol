// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";

contract DeployVaults is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address[] vaults;
    string configPath = "-vaults-20251006-2.json";

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
        console.log("Using existing WhitelistManager at:", address(coreContracts.whitelistManager));
        console.log("Using existing TermMaxVaultFactoryV2 at:", address(coreContracts.vaultFactory));
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);

        VaultInitialParamsV2[] memory vaultParams = JsonLoader.getVaultConfigsFromJson(vm.readFile(configPath));
        for (uint256 i; i < vaultParams.length; i++) {
            VaultInitialParamsV2 memory params = vaultParams[i];
            params.admin = address(coreContracts.accessManager);
            console.log("Deploying TermMaxVaultV2 index:", i);
            console.log("  Vault name:", params.name);
            console.log("  Vault symbol:", params.symbol);
            console.log("  Vault admin:", params.admin);
            console.log("  Vault curator:", params.curator);
            console.log("  Vault guardian:", params.guardian);
            console.log("  Vault asset:", address(params.asset));
            console.log("  Vault pool:", address(params.pool));
            console.log("  Vault guardian:", params.guardian);
            console.log("  Vault timelock (s):", params.timelock);
            console.log("  Vault maxCapacity:", params.maxCapacity);
            console.log("  Vault minimal apy:", params.minApy);

            address vault = coreContracts.vaultFactory.createVault(params, 0);
            console.log("Deployed TermMaxVaultV2 at:", vault);
            vaults.push(vault);
        }
        console.log("Submit all deployed vaults to WhitelistManager");
        // whitelist the vault
        coreContracts.accessManager.batchSetWhitelist(
            coreContracts.whitelistManager,
            vaults, // updated to use the vaults array
            IWhitelistManager.ContractModule.ORDER_CALLBACK,
            true
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
        for (uint256 i = 0; i < vaults.length; i++) {
            deploymentEnv = string(
                abi.encodePacked(deploymentEnv, "VAULT_ADDRESS_", vm.toString(i + 1), "=", vm.toString(vaults[i]), "\n")
            );
        }

        string memory path = string.concat(
            vm.projectRoot(),
            "/deployments/",
            coreParams.network,
            "/",
            coreParams.network,
            "-v2-vaults-",
            vm.toString(block.timestamp),
            ".env"
        );
        vm.writeFile(path, deploymentEnv);
    }
}
