// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/v1/TermMaxMarket.sol";
import {TermMaxOrder, ISwapCallback} from "contracts/v1/TermMaxOrder.sol";
import {ITermMaxOrder} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MarketConfig, OrderConfig, CurveCuts, CurveCut} from "contracts/v1/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "contracts/v1/test/MockSwapAdapter.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {FaucetERC20} from "contracts/v1/test/testnet/FaucetERC20.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract DeployOrder is DeployBase {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;
    address priceFeedOperatorAddr;

    // address config - should be set in the setup function based on the network
    address marketAddr;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");
        string memory priceFeedOperatorVar = string.concat(networkUpper, "_PRICE_FEED_OPERATOR_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);
        priceFeedOperatorAddr = vm.envAddress(priceFeedOperatorVar);

        // Set market address based on network
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-sepolia"))) {
            marketAddr = address(0xD0586B5a5F97347C769983C404348346FE26f38e);
        } else {
            // For other networks, the market address should be provided via environment
            // or read from deployment JSON files
            string memory marketAddressVar = string.concat(networkUpper, "_MARKET_ADDRESS");
            try vm.envAddress(marketAddressVar) returns (address addr) {
                marketAddr = addr;
            } catch {
                // Try to load from deployment files
                try vm.readFile(string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-market.json"))
                returns (string memory json) {
                    try vm.parseJsonAddress(json, ".contracts.market") returns (address addr) {
                        marketAddr = addr;
                    } catch {
                        revert("Market address not found in environment or deployment files");
                    }
                } catch {
                    revert("Market address not found in environment and market deployment file not found");
                }
            }
        }
    }

    function run() public {
        uint256 currentBlockNum = block.number;
        TermMaxMarket market = TermMaxMarket(marketAddr);
        vm.startBroadcast(deployerPrivateKey);
        uint256 maxXtReserve = 200000000000;
        CurveCut memory lendCurveCut0 = CurveCut({xtReserve: 0, liqSquare: 461683991532123062272, offset: 33973665961});
        CurveCut memory lendCurveCut1 =
            CurveCut({xtReserve: 9000000000, liqSquare: 425141100695200464896, offset: 32237899859});
        CurveCut memory lendCurveCut2 =
            CurveCut({xtReserve: 21000000000, liqSquare: 1072059478286836826112, offset: 63540304430});
        CurveCut[] memory _lendCurveCuts = new CurveCut[](3);
        _lendCurveCuts[0] = lendCurveCut0;
        _lendCurveCuts[1] = lendCurveCut1;
        _lendCurveCuts[2] = lendCurveCut2;

        CurveCut memory borrowCurveCut0 =
            CurveCut({xtReserve: 0, liqSquare: 330638754635872993280, offset: 29116862443});
        CurveCut memory borrowCurveCut1 =
            CurveCut({xtReserve: 8000000000, liqSquare: 361237873939795017728, offset: 30796362980});
        CurveCut memory borrowCurveCut2 =
            CurveCut({xtReserve: 20000000000, liqSquare: 826934466947518169088, offset: 56854893632});
        CurveCut[] memory _borrowCurveCuts = new CurveCut[](3);
        _borrowCurveCuts[0] = borrowCurveCut0;
        _borrowCurveCuts[1] = borrowCurveCut1;
        _borrowCurveCuts[2] = borrowCurveCut2;

        CurveCuts memory curveCuts = CurveCuts({lendCurveCuts: _lendCurveCuts, borrowCurveCuts: _borrowCurveCuts});
        ITermMaxOrder order = market.createOrder(deployerAddr, maxXtReserve, ISwapCallback(address(0)), curveCuts);

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Order Info =====");
        console.log("Network:", network);
        console.log("Market Address:", marketAddr);
        console.log("Order Maker:", deployerAddr);
        console.log("Order Address:", address(order));
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");
    }
}
