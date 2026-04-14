// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {DeployBaseV2} from "script/deploy/DeployBaseV2.s.sol";
import {TermMaxB2TokenPriceFeedAdapter} from "contracts/v2/oracle/adapters/b2/TermMaxB2TokenPriceFeedAdapter.sol";

/**
 * @title DeployB2BTCUSDOracle
 * @notice Deploy script for TermMax B2 BTC/USD oracle adapter
 * @dev Deploys TermMaxB2TokenPriceFeedAdapter with fixed BTC/USD pair settings
 */
contract DeployB2BTCUSDOracle is DeployBaseV2 {
    uint256 internal constant BTC_USD_INDEX = 18;
    address internal constant SUPRA_SVALUE_FEED = 0xD02cc7a670047b6b012556A88e275c685d25e0c9;

    string internal network;
    address internal deployerAddr;
    uint256 internal deployerPrivateKey;

    function setUp() public {
        network = vm.envOr("NETWORK", string("b2-mainnet"));
        string memory networkUpper = StringHelper.toUpper(network);

        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);

        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        console.log("===== Deployment Configuration =====");
        console.log("Network:", network);
        console.log("Deployer:", deployerAddr);
        console.log("Deployer balance:", deployerAddr.balance);
        console.log("BTC/USD index:", BTC_USD_INDEX);
        console.log("Supra value feed:", SUPRA_SVALUE_FEED);
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        TermMaxB2TokenPriceFeedAdapter adapter = new TermMaxB2TokenPriceFeedAdapter(BTC_USD_INDEX, SUPRA_SVALUE_FEED);

        vm.stopBroadcast();

        console.log("\n===== Deployment Successful =====");
        console.log("TermMaxB2TokenPriceFeedAdapter deployed at:", address(adapter));

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        console.log("\n===== Oracle Data =====");
        console.log("Decimals:", adapter.decimals());
        console.log("Description:", adapter.description());
        console.log("Round ID:", roundId);
        console.log("BTC/USD Price:", answer);
        console.log("Started At (sec):", startedAt);
        console.log("Updated At (sec):", updatedAt);
        console.log("Answered In Round:", answeredInRound);

        _saveDeploymentInfo(address(adapter));
    }

    function _saveDeploymentInfo(address adapterAddress) internal {
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
                '    "termMaxB2BTCUSDOracle": "',
                vm.toString(adapterAddress),
                '",\n',
                '    "supraSValueFeed": "',
                vm.toString(SUPRA_SVALUE_FEED),
                '",\n',
                '    "pairIndex": "',
                vm.toString(BTC_USD_INDEX),
                '"\n',
                "  }\n",
                "}"
            )
        );

        string memory jsonPath = string.concat(
            vm.projectRoot(),
            "/deployments/",
            network,
            "/",
            network,
            "-b2-btc-usd-oracle-",
            vm.toString(block.timestamp),
            ".json"
        );
        vm.writeFile(jsonPath, json);
        console.log("Deployment info saved to:", jsonPath);
    }
}
