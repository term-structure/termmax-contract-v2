// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract GenerateWallets is Script {
    function run() public {
        string memory mnemonic = vm.envString("MAINNET_FORK_MNEMONIC");

        uint256 accountNum = 5;

        for (uint32 i = 0; i < accountNum; i++) {
            (address deployer, uint256 privateKey) = deriveRememberKey(mnemonic, i);
            console.log("Addr", i, ":", deployer);
            console.log("PrivateKey", i, ":", privateKey);
        }

        // bytes32 hash = keccak256("Signed by deployer");
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // vm.startBroadcast(deployer);

        // vm.stopBroadcast();
    }
}
