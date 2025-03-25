// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {JsonLoader} from "./utils/JsonLoader.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {StringHelper} from "./utils/StringHelper.sol";
import {AccessManager} from "contracts/access/AccessManager.sol";

contract SubmitOracles is Script {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address oracleAggregatorAddr;
    address accessManagerAddr;
    JsonLoader.Config[] configs;
    mapping(address => bool) tokenSubmitted;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);
        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        deployerPrivateKey = vm.envUint(privateKeyVar);

        string memory accessManagerPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(accessManagerPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        string memory corePath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        json = vm.readFile(corePath);

        oracleAggregatorAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
    }

    function run() public {
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, ".json");

        vm.startBroadcast(deployerPrivateKey);

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        AccessManager accessManager = AccessManager(accessManagerAddr);
        OracleAggregator oracle = OracleAggregator(oracleAggregatorAddr);
        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];
            (AggregatorV3Interface aggregator,,) = oracle.oracles(address(config.underlyingConfig.tokenAddr));
            if (
                !tokenSubmitted[address(config.underlyingConfig.tokenAddr)]
                    && (
                        address(aggregator) == address(0)
                            || address(aggregator) != address(config.underlyingConfig.priceFeedAddr)
                    )
            ) {
                accessManager.submitPendingOracle(
                    oracle,
                    address(config.underlyingConfig.tokenAddr),
                    IOracle.Oracle(
                        AggregatorV3Interface(config.underlyingConfig.priceFeedAddr),
                        AggregatorV3Interface(config.underlyingConfig.priceFeedAddr),
                        uint32(config.underlyingConfig.heartBeat)
                    )
                );
                tokenSubmitted[address(config.underlyingConfig.tokenAddr)] = true;
                console.log(
                    "Submitted oracle for underlying: ",
                    IERC20Metadata(address(config.underlyingConfig.tokenAddr)).symbol()
                );
                console.log("Price feed: ", config.underlyingConfig.priceFeedAddr);
                console.log("Heartbeat: ", config.underlyingConfig.heartBeat);
                console.log("--------------------------------");
            }
            (aggregator,,) = oracle.oracles(address(config.collateralConfig.tokenAddr));
            if (
                !tokenSubmitted[address(config.collateralConfig.tokenAddr)]
                    && (
                        address(aggregator) == address(0)
                            || address(aggregator) != address(config.collateralConfig.priceFeedAddr)
                    )
            ) {
                accessManager.submitPendingOracle(
                    oracle,
                    address(config.collateralConfig.tokenAddr),
                    IOracle.Oracle(
                        AggregatorV3Interface(config.collateralConfig.priceFeedAddr),
                        AggregatorV3Interface(config.collateralConfig.priceFeedAddr),
                        uint32(config.collateralConfig.heartBeat)
                    )
                );
                tokenSubmitted[address(config.collateralConfig.tokenAddr)] = true;
                console.log(
                    "Submitted oracle for collateral: ",
                    IERC20Metadata(address(config.collateralConfig.tokenAddr)).symbol()
                );
                console.log("Price feed: ", config.collateralConfig.priceFeedAddr);
                console.log("Heartbeat: ", config.collateralConfig.heartBeat);
                console.log("--------------------------------");
            }
        }

        vm.stopBroadcast();
    }
}
