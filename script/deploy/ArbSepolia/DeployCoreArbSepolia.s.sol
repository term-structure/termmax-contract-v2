// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../../../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken} from "../../../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "../../../contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {DeployBase} from "../DeployBase.s.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";

contract DeployCoreArbSepolia is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        (
            Faucet faucet,
            TermMaxFactory factory,
            TermMaxRouter router,
            SwapAdapter swapAdapter
        ) = deployCore(adminAddr);
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Core Info =====");
        console.log("Deplyer:", deployerAddr);
        console.log("Admin:", adminAddr);
        console.log("Faucet deployed at:", address(faucet));
        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));
        console.log("SwapAdapter deployed at:", address(swapAdapter));
    }
}
