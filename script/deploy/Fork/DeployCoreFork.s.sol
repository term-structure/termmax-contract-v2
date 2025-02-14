// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";
import {DeployBase} from "../DeployBase.s.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";
import {KyberswapV2Adapter} from "contracts/router/swapAdapters/KyberswapV2Adapter.sol";
import {OdosV2Adapter} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {UniswapV3Adapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";

contract DeployCoreFork is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("FORK_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("FORK_ADMIN_ADDRESS");
    address uniswapV3RouterAddr = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address odosV2RouterAddr = address(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
    address pendleSwapV3RouterAddr = address(0x888888888889758F76e7103c6CbF23ABbF58F946);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        (
            ITermMaxFactory factory,
            IVaultFactory vaultFactory,
            IOracle oracleAggregator,
            ITermMaxRouter router,
            UniswapV3Adapter uniswapV3Adapter,
            OdosV2Adapter odosV2Adapter,
            PendleSwapV3Adapter pendleSwapV3Adapter
        ) = deployCoreMainnet(adminAddr, uniswapV3RouterAddr, odosV2RouterAddr, pendleSwapV3RouterAddr);
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
        console.log("VaultFactory deployed at:", address(vaultFactory));
        console.log("Oracle Aggregator deployed at:", address(oracleAggregator));
        console.log("Router deployed at:", address(router));
        console.log("UniswapV3Adapter deployed at:", address(uniswapV3Adapter));
        console.log("OdosV2Adapter deployed at:", address(odosV2Adapter));
        console.log("PendleSwapV3Adapter deployed at:", address(pendleSwapV3Adapter));
        console.log();
    }
}
