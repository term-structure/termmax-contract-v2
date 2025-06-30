// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {FaucetERC20} from "contracts/v1/test/testnet/FaucetERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ForkDevTest is Test {
    // string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // vm.createSelectFork(MAINNET_RPC_URL, 351581649); // Fork block
    }

    function testL() public {
        uint256 a1 = 8520554372986253838;
        uint256 a2 = 2315440372228375033;
        console.log((a1 + a2) / 10);

        uint256 p1 = 426130346645352599;
        uint256 p2 = 115799907525091444;
        console.log(p1 * 2 + p2 * 2);
    }
}
