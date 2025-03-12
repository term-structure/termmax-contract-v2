// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {TermMaxOrder, ISwapCallback} from "contracts/TermMaxOrder.sol";
import {ITermMaxOrder} from "contracts/TermMaxOrder.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MarketConfig, OrderConfig, CurveCuts, CurveCut} from "contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "contracts/test/MockSwapAdapter.sol";
import {JsonLoader} from "../../utils/JsonLoader.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "contracts/test/testnet/FaucetERC20.sol";
import {DeployBase} from "../DeployBase.s.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";

contract DeloyVaultArbSepolia is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");

    // address config
    address vaultFactoryAddr;
    uint256 timelock = 0;
    address[] assetAddrs = [address(0x678FE35c9755FBfDBe110400Dfd6B9D86920BA5B)];
    uint256 maxCapacity = type(uint128).max;
    string[] names = ["VAULT-USDC"];
    uint64 performanceFeeRate = 0.1e8;

    function loadAddressConfig() internal {
        string memory deploymentPath = string.concat(vm.projectRoot(), "/deployments/arb-sepolia/arb-sepolia-core.json");
        string memory json = vm.readFile(deploymentPath);

        vaultFactoryAddr = vm.parseJsonAddress(json, ".contracts.vaultFactory");

        console.log("Loaded addresses from deployment file:");
        console.log("  VaultFactory:", vaultFactoryAddr);
    }

    function run() public {
        loadAddressConfig();
        uint256 currentBlockNum = block.number;
        vm.startBroadcast(deployerPrivateKey);
        VaultFactory vaultFactory = VaultFactory(vaultFactoryAddr);

        ITermMaxVault[] memory vaults = new ITermMaxVault[](assetAddrs.length);
        for (uint256 i = 0; i < assetAddrs.length; i++) {
            console.log("Deploying vault at index", i);
            vaults[i] = deployVault(
                address(vaultFactory),
                adminAddr,
                address(0),
                timelock,
                assetAddrs[i],
                maxCapacity,
                names[i],
                names[i],
                performanceFeeRate
            );

            // Write individual vault info to JSON
            string memory vaultPath =
                string.concat(vm.projectRoot(), "/deployments/arb-sepolia/arb-sepolia-vault-", names[i], ".json");
            string memory vaultJson = string.concat(
                "{",
                '"name": "',
                names[i],
                '",',
                '"address": "',
                vm.toString(address(vaults[i])),
                '",',
                '"asset": "',
                vm.toString(assetAddrs[i]),
                '",',
                '"deploymentBlock": ',
                vm.toString(currentBlockNum),
                ",",
                '"gitBranch": "',
                getGitBranch(),
                '",',
                '"gitCommit": "',
                vm.toString(getGitCommitHash()),
                '",',
                '"performanceFeeRate": ',
                vm.toString(performanceFeeRate),
                ",",
                '"maxCapacity": "',
                vm.toString(maxCapacity),
                '",',
                '"timelock": ',
                vm.toString(timelock),
                ",",
                '"admin": "',
                vm.toString(adminAddr),
                '"',
                "}"
            );
            vm.writeFile(vaultPath, vaultJson);
            console.log("Vault info written to:", vaultPath);
        }
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Vault Info =====");
        for (uint256 i = 0; i < names.length; i++) {
            console.log("Vault", names[i], ":", address(vaults[i]));
        }
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");
    }
}
