// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MarketViewer} from "contracts/v1/router/MarketViewer.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract DeployMarketViewer is Script {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);
    }

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddr);
        console.log("Deployer balance: ", deployerAddr.balance);
        MarketViewer marketViewer = new MarketViewer();
        console.log("MarketViewer deployed at: ", address(marketViewer));

        vm.stopBroadcast();
    }
}
