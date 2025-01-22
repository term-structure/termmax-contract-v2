// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../../contracts/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "../../../contracts/router/ITermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../../contracts/TermMaxMarket.sol";
import {MockERC20} from "../../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../../../contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../../contracts/tokens/IMintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "../../../contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {DeployBase} from "../DeployBase.s.sol";
import {IOracle} from "../../../contracts/oracle/IOracle.sol";

contract DeployCoreHolesky is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("HOLESKY_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("HOLESKY_ADMIN_ADDRESS");

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        (
            ITermMaxFactory factory,
            IOracle oracleAggregator,
            ITermMaxRouter router,
            SwapAdapter swapAdapter,
            Faucet faucet
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
        console.log("Factory deployed at:", address(factory));
        console.log("Oracle Aggregator deployed at:", address(oracleAggregator));
        console.log("Router deployed at:", address(router));
        console.log("SwapAdapter deployed at:", address(swapAdapter));
        console.log("Faucet deployed at:", address(faucet));
    }
}
