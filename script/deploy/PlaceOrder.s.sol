// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OrderConfig, CurveCut} from "contracts/v1/storage/TermMaxStorage.sol";
import {JsonLoader} from "script/utils/JsonLoader.sol";
import {OrderV2ConfigurationParams} from "contracts/v2/vault/VaultStorageV2.sol";
import {ITermMaxOrderV2} from "contracts/v2/ITermMaxOrderV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";

contract PlaceOrder is DeployBaseV2 {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    string configPath = "-order.json";

    // Data parsed from single order json (arb-sepolia-order.json style)
    struct ParsedOrderJson {
        address market;
        address maker;
        uint256 virtualXtReserve;
        address pool;
        uint256 initialLiquidity;
        OrderConfig orderConfig;
    }

    // ------------------------- JSON PARSING (Single Order) -------------------------
    function _parseSingleOrderJson(string memory jsonData) internal view returns (ParsedOrderJson memory p) {
        // maker / pool may be placeholder. Ensure valid hex before attempting readAddress to avoid revert.
        // We expect user to replace placeholder addresses with real ones prior to execution.
        p.market = vm.parseJsonAddress(jsonData, ".market");
        p.maker = vm.parseJsonAddress(jsonData, ".maker");
        p.pool = vm.parseJsonAddress(jsonData, ".pool");
        p.virtualXtReserve = vm.parseJsonUint(jsonData, ".virtualXtReserve");
        p.initialLiquidity = vm.parseJsonUint(jsonData, ".initialLiquidity");
        // orderConfig
        string memory orderConfigPrefix = ".orderConfig";
        OrderConfig memory oc = JsonLoader.getOrderConfigFromJson(jsonData, orderConfigPrefix);
        p.orderConfig = oc;
    }

    function _getCurveString(CurveCut memory c) internal pure returns (string memory) {
        return string.concat(
            "xtReserve=",
            vm.toString(c.xtReserve),
            " liqSquare=",
            vm.toString(c.liqSquare),
            " offset=",
            vm.toString(c.offset)
        );
    }

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        configPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, configPath);
        // Load network-specific configuration
        {
            string memory networkUpper = toUpper(network);
            string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
            string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

            deployerPrivateKey = vm.envUint(privateKeyVar);
            adminAddr = vm.envAddress(adminVar);
            coreParams.adminAddr = adminAddr;
            deployerAddr = vm.addr(deployerPrivateKey);

            console.log("Admin:", adminAddr);
            console.log("Deployer:", deployerAddr);
        }

        string memory deploymentPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(deploymentPath);
        address accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        deploymentPath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core-v2.json");
        json = vm.readFile(deploymentPath);
        coreContracts = readDeployData(json);
        console.log("Using existing AccessManagerV2 at:", accessManagerAddr);
        coreContracts.accessManager = AccessManagerV2(accessManagerAddr);
    }

    function run() public {
        console.log("Network:", network);
        console.log("Deployer balance:", deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        // Detect whether config file is single order json (contains .orderConfig) or market configs list
        string memory rawJson = vm.readFile(configPath);
        ParsedOrderJson memory parsed = _parseSingleOrderJson(rawJson);
        {
            console.log("Single Order JSON detected. Parsed values:");
            console.log("  Market:", parsed.market);
            console.log("  Maker:", parsed.maker);
            console.log("  Virtual XT Reserve:", parsed.virtualXtReserve);
            console.log("  Initial Liquidity:", parsed.initialLiquidity);
            console.log("  Pool (may be zero if placeholder):", parsed.pool);
            console.log("  OrderConfig.gtId:", parsed.orderConfig.gtId);
            console.log("  OrderConfig.maxXtReserve:", parsed.orderConfig.maxXtReserve);
            console.log("  Lend curve cuts length:", parsed.orderConfig.curveCuts.lendCurveCuts.length);
            for (uint256 i; i < parsed.orderConfig.curveCuts.lendCurveCuts.length; i++) {
                CurveCut memory c = parsed.orderConfig.curveCuts.lendCurveCuts[i];
                string memory str = string.concat("    Lend[", vm.toString(i), "] ", _getCurveString(c));
                console.log(str);
            }
            console.log("  Borrow curve cuts length:", parsed.orderConfig.curveCuts.borrowCurveCuts.length);
            for (uint256 i; i < parsed.orderConfig.curveCuts.borrowCurveCuts.length; i++) {
                CurveCut memory c2 = parsed.orderConfig.curveCuts.borrowCurveCuts[i];
                string memory str = string.concat("    Borrow[", vm.toString(i), "] ", _getCurveString(c2));
                console.log(str);
            }
        }
        // Place order on TermMaxOrderV2
        TermMaxMarketV2 market = TermMaxMarketV2(parsed.market);
        OrderInitialParams memory params;
        params.maker = parsed.maker;
        params.virtualXtReserve = uint128(parsed.virtualXtReserve);
        params.pool = IERC4626(parsed.pool);
        params.orderConfig = parsed.orderConfig;

        address order = address(market.createOrder(params));
        console.log("Order created at address:", order);
        require(TermMaxOrderV2(order).maker() == parsed.maker, "Order maker mismatch");
        if (parsed.initialLiquidity > 0) {
            (IERC20 ft, IERC20 xt,,, IERC20 debtToken) = market.tokens(); // Placeholder for adding liquidity logic
            debtToken.approve(address(market), parsed.initialLiquidity);
            market.mint(order, parsed.initialLiquidity);
            require(ft.balanceOf(order) == parsed.initialLiquidity, "Initial liquidity mint failed");
            require(xt.balanceOf(order) == parsed.initialLiquidity, "Initial liquidity mint failed");
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
