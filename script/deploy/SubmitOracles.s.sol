// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract SubmitOracles is Script {
    // Network-specific config loaded from environment variables
    string network;
    uint256 oracleAggregatorAdminPrivateKey;
    address oracleAggregatorAddr;
    JsonLoader.Config[] configs;
    mapping(address => bool) tokenSubmitted;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);
        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY");
        oracleAggregatorAdminPrivateKey = vm.envUint(privateKeyVar);

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        string memory json = vm.readFile(deploymentPath);

        oracleAggregatorAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
    }

    function run() public {
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, ".json");

        vm.startBroadcast(oracleAggregatorAdminPrivateKey);

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        OracleAggregator oracle = OracleAggregator(oracleAggregatorAddr);
        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];
            if (!tokenSubmitted[address(config.underlyingConfig.tokenAddr)]) {
                oracle.submitPendingOracle(
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
            if (!tokenSubmitted[address(config.collateralConfig.tokenAddr)]) {
                oracle.submitPendingOracle(
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
