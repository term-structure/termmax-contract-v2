// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";
import {TermMaxOndoPriceFeedAdapterFactory} from
    "contracts/v2/oracle/adapters/ondo/TermMaxOndoPriceFeedAdapterFactory.sol";

/**
 * @title DeployOndoPriceFeedAdapterFactory
 * @notice Script to deploy TermMaxOndoPriceFeedAdapterFactory
 * @dev Env vars:
 *      - NETWORK (default: eth-mainnet)
 *      - {NETWORK}_DEPLOYER_PRIVATE_KEY
 *      - {NETWORK}_ONDO_ORACLE (optional, fallback to fork-test value)
 *      - {NETWORK}_PRICE_FEED_FACTORY_V2 (optional, fallback to deployments/{network}/{network}-core-v2.json)
 */
contract DeployOndoPriceFeedAdapterFactory is DeployBaseV2 {
    error PriceFeedFactoryNotConfigured();

    string public network;
    address public deployerAddr;
    uint256 public deployerPrivateKey;

    address public ondoOracle;
    DeployedContracts coreContracts;

    function setUp() public {
        network = vm.envOr("NETWORK", string("eth-mainnet"));
        string memory networkUpper = StringHelper.toUpper(network);

        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);

        ondoOracle = vm.envAddress(string.concat(networkUpper, "_ONDO_ORACLE"));

        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core-v2.json");
        string memory json = vm.readFile(deploymentPath);
        coreContracts = readDeployData(json);

        console.log("===== Deployment Configuration =====");
        console.log("Network:", network);
        console.log("Deployer:", deployerAddr);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("Ondo Oracle:", ondoOracle);
        console.log("PriceFeedFactoryV2:", address(coreContracts.priceFeedFactory));

        require(ondoOracle != address(0), "Ondo Oracle address must be set");
        require(address(coreContracts.priceFeedFactory) != address(0), "PriceFeedFactoryV2 address must be set");
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TermMaxOndoPriceFeedAdapterFactory factory =
            new TermMaxOndoPriceFeedAdapterFactory(ondoOracle, address(coreContracts.priceFeedFactory));
        vm.stopBroadcast();

        console.log("===== Deployment Successful =====");
        console.log("TermMaxOndoPriceFeedAdapterFactory:", address(factory));
        console.log("Factory ondoOracle:", factory.ondoOracle());
        console.log("Factory priceFeedFactory:", address(factory.priceFeedFactory()));

        saveDeploymentInfo(address(factory));
    }

    function saveDeploymentInfo(address factoryAddress) internal {
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                network,
                '",\n',
                '  "deployedAt": "',
                vm.toString(block.timestamp),
                '",\n',
                '  "gitBranch": "',
                getGitBranch(),
                '",\n',
                '  "gitCommitHash": "',
                vm.toString(getGitCommitHash()),
                '",\n',
                '  "blockInfo": {\n',
                '    "number": "',
                vm.toString(block.number),
                '",\n',
                '    "timestamp": "',
                vm.toString(block.timestamp),
                '"\n',
                "  },\n",
                '  "deployer": "',
                vm.toString(deployerAddr),
                '",\n',
                '  "contracts": {\n',
                '    "termMaxOndoPriceFeedAdapterFactory": "',
                vm.toString(factoryAddress),
                '",\n',
                '    "ondoOracle": "',
                vm.toString(ondoOracle),
                '",\n',
                '    "priceFeedFactoryV2": "',
                vm.toString(address(coreContracts.priceFeedFactory)),
                '"\n',
                "  }\n",
                "}"
            )
        );

        string memory jsonPath = string.concat(
            vm.projectRoot(), "/deployments/", network, "/", network, "-ondo-price-feed-adapter-factory.json"
        );
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
