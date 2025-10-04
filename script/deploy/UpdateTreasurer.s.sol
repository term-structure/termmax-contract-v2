// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OrderConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {JsonLoader} from "script/utils/JsonLoader.sol";
import {OrderV2ConfigurationParams} from "contracts/v2/vault/VaultStorageV2.sol";
import {ITermMaxOrderV2} from "contracts/v2/ITermMaxOrderV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {TermMaxMarketV2} from "contracts/v2/TermMaxMarketV2.sol";

contract DeployMarketsScript is DeployBaseV2 {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address treasurerAddr;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        // Load network-specific configuration
        {
            string memory networkUpper = toUpper(network);
            string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
            string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

            deployerPrivateKey = vm.envUint(privateKeyVar);
            adminAddr = vm.envAddress(adminVar);
            deployerAddr = vm.addr(deployerPrivateKey);
            treasurerAddr = vm.envAddress(string.concat(networkUpper, "_TREASURER_ADDRESS"));

            console.log("Admin:", adminAddr);
            console.log("Deployer:", deployerAddr);
            console.log("Treasurer:", treasurerAddr);
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        coreContracts.accessManager = AccessManagerV2(vm.parseJsonAddress(json, ".contracts.accessManager"));
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);
        address[] memory markets = new address[](4);
        markets[0] = 0x6e4b0B37f45E85467AAEF5504d7262C45f047D88;
        markets[1] = 0xE3C3eC217C779D854b1Cf4A8260B35378B5C5d78;
        markets[2] = 0xA4E200dc744640A7205008E0667ADBe861EE71fa;
        markets[3] = 0xe36212B6800C07dB575d29444547535dEBd92D64;

        vm.startBroadcast(deployerPrivateKey);
        {
            for (uint256 i = 0; i < markets.length; i++) {
                MarketConfig memory config = TermMaxMarketV2(markets[i]).config();
                console.log("Market:", markets[i]);
                console.log("  Name:", IERC20Metadata(markets[i]).name());
                config.treasurer = treasurerAddr;
                coreContracts.accessManager.updateMarketConfig(ITermMaxMarket(markets[i]), config);
            }
        }
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log();
    }
}
