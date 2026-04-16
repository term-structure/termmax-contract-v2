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
import {SimpleAggregator} from "contracts/v2/oracle/SimpleAggregator.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";

contract DeployOracleAggregatorV2 is DeployBaseV2 {
    using StringHelper for string;
    // Network-specific config loaded from environment variables

    uint256 deployerPrivateKey;

    CoreParams coreParams;
    DeployedContracts coreContracts;
    bool isBroadcast;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        isBroadcast = vm.envBool("IS_BROADCAST");
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");
        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        coreParams.adminAddr = vm.envAddress(adminVar);
        coreParams.oracleTimelock = vm.envUint(string.concat(networkUpper, "_ORACLE_TIMELOCK"));

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
        if (coreParams.isL2Network) {
            string memory l2SequencerUptimeFeedVar = string.concat(networkUpper, "_L2_SEQUENCER_UPTIME_FEED");
            coreParams.l2SequencerUpPriceFeed = vm.envAddress(l2SequencerUptimeFeedVar);
            string memory l2SequencerGracePeriodVar = string.concat(networkUpper, "_L2_SEQUENCER_GRACE_PERIOD");
            coreParams.l2GracePeriod = vm.envUint(l2SequencerGracePeriodVar);
        }

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-access-manager.json"
        );
        string memory json = vm.readFile(deploymentPath);
        address accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

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

        coreContracts.oracle = coreParams.isL2Network
            ? IOracle(
                address(
                    deployOracleAggregatorWithSequencer(
                        coreParams.deployerAddr,
                        coreParams.oracleTimelock,
                        coreParams.l2SequencerUpPriceFeed,
                        coreParams.l2GracePeriod
                    )
                )
            )
            : IOracle(address(deployOracleAggregator(address(coreContracts.accessManager), coreParams.oracleTimelock)));
        console.log("Deployed OracleAggregatorV2 at:", address(coreContracts.oracle));

        if (coreParams.isL2Network) {
            OracleAggregatorV2(address(coreContracts.oracle)).transferOwnership(address(coreContracts.accessManager));
            console.log("Transferred ownership of OracleAggregatorV2 to AccessManagerV2");
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

        if (isBroadcast) {
            writeAsJson(
                string.concat(
                    vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
                ),
                coreParams,
                coreContracts
            );
        }
    }
}
