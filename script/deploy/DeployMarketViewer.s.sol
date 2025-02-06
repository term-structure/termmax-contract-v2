// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MarketViewer} from "../../contracts/router/MarketViewer.sol";

contract DeployMarketViewer is Script {
    // deployer config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddr);
        console.log("Deployer balance: ", deployerAddr.balance);
        MarketViewer marketViewer = new MarketViewer();
        console.log("MarketViewer deployed at: ", address(marketViewer));

        vm.stopBroadcast();
    }
}
