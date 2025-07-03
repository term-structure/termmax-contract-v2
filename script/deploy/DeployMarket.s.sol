// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/v1/TermMaxMarket.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {OracleAggregator} from "contracts/v1/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "contracts/v1/test/MockSwapAdapter.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {FaucetERC20} from "contracts/v1/test/testnet/FaucetERC20.sol";
import {DeployBase} from "./DeployBase.s.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract DeloyMarket is DeployBase {
    // Network-specific config loaded from environment variables
    string network;
    uint256 deployerPrivateKey;
    address deployerAddr;
    address adminAddr;
    address treasurerAddr;
    uint256 collateralCapForGt;
    address priceFeedOperatorAddr;

    address accessManagerAddr;
    address factoryAddr;
    address oracleAddr;
    address routerAddr;
    address faucetAddr;
    TermMaxMarket[] markets;
    JsonLoader.Config[] configs;
    Faucet faucet;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");
        string memory treasurerVar = string.concat(networkUpper, "_TREASURER_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);
        treasurerAddr = vm.envAddress(treasurerVar);
        if (
            keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("eth-mainnet"))
                && keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("arb-mainnet"))
        ) {
            string memory priceFeedOperatorVar = string.concat(networkUpper, "_PRICE_FEED_OPERATOR_ADDRESS");
            priceFeedOperatorAddr = vm.envAddress(priceFeedOperatorVar);
        }
    }

    function loadAddressConfig() internal {
        string memory accessManagerPath =
            string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-access-manager.json");
        string memory json = vm.readFile(accessManagerPath);
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        string memory corePath = string.concat(vm.projectRoot(), "/deployments/", network, "/", network, "-core.json");
        json = vm.readFile(corePath);

        factoryAddr = vm.parseJsonAddress(json, ".contracts.factory");
        oracleAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
        routerAddr = vm.parseJsonAddress(json, ".contracts.router");
        if (
            keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("eth-mainnet"))
                && keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("arb-mainnet"))
        ) {
            faucetAddr = vm.parseJsonAddress(json, ".contracts.faucet");
        }
    }

    function run() public {
        loadAddressConfig();

        uint256 currentBlockNum = block.number;
        uint256 currentTimestamp = block.timestamp;
        faucet = Faucet(faucetAddr);
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/", network, ".json");

        vm.startBroadcast(deployerPrivateKey);
        if (
            keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("eth-mainnet"))
                || keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))
        ) {
            (markets, configs) =
                deployMarketsMainnet(accessManagerAddr, factoryAddr, oracleAddr, deployDataPath, treasurerAddr);
        } else {
            (markets, configs) = deployMarkets(
                accessManagerAddr,
                factoryAddr,
                oracleAddr,
                faucetAddr,
                deployDataPath,
                treasurerAddr,
                priceFeedOperatorAddr
            );
        }

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", currentBlockNum);
        console.log("Block timestamp:", currentTimestamp);
        console.log();

        console.log("===== Address Info =====");
        console.log("Deplyer:", deployerAddr);
        if (
            keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("eth-mainnet"))
                && keccak256(abi.encodePacked(network)) != keccak256(abi.encodePacked("arb-mainnet"))
        ) {
            console.log("Price Feed Operator:", priceFeedOperatorAddr);
        }
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");

        for (uint256 i = 0; i < markets.length; i++) {
            console.log("===== Market Info - %d =====", i);
            printMarketConfig(markets[i], configs[i]);
            console.log("");
        }
    }

    function printMarketConfig(TermMaxMarket market, JsonLoader.Config memory config) public {
        MarketConfig memory marketConfig = market.config();
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateralAddr, IERC20 underlying) =
            market.tokens();

        console.log("Market deployed at:", address(market));
        console.log("Market name:", config.marketName);
        console.log("Market symbol:", config.marketSymbol);
        console.log("Collateral (%s) address: %s", IERC20Metadata(collateralAddr).symbol(), address(collateralAddr));
        console.log("Underlying (%s) address: %s", IERC20Metadata(address(underlying)).symbol(), address(underlying));
        console.log("Collateral price feed address:", config.collateralConfig.priceFeedAddr);
        console.log("Collateral heartbeat:", config.collateralConfig.heartBeat);
        console.log("Underlying price feed address:", config.underlyingConfig.priceFeedAddr);
        console.log("Underlying heartbeat:", config.underlyingConfig.heartBeat);

        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("GT deployed at:", address(gt));

        console.log();

        console.log("Treasurer:", treasurerAddr);
        console.log("Maturity:", StringHelper.convertTimestampToDateString(marketConfig.maturity, "YYYY-MM-DD"));
        console.log("Salt:", config.salt);
        console.log("Lend Taker Fee Ratio:", marketConfig.feeConfig.lendTakerFeeRatio);
        console.log("Lend Maker Fee Ratio:", marketConfig.feeConfig.lendMakerFeeRatio);
        console.log("Borrow Taker Fee Ratio:", marketConfig.feeConfig.borrowTakerFeeRatio);
        console.log("Borrow Maker Fee Ratio:", marketConfig.feeConfig.borrowMakerFeeRatio);
        console.log("Mint GT Fee Ratio:", marketConfig.feeConfig.mintGtFeeRatio);
        console.log("Issue FT Fee Ref:", marketConfig.feeConfig.mintGtFeeRef);

        // Write market config to JSON file
        string memory marketFileName = _getMarketFileName(collateralAddr, address(underlying), marketConfig.maturity);
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        string memory marketFilePath = string.concat(deploymentsDir, "/", marketFileName);
        vm.writeFile(
            marketFilePath,
            _createMarketJson(
                market,
                marketConfig,
                ft,
                xt,
                gt,
                collateralAddr,
                underlying,
                config.collateralConfig.priceFeedAddr,
                uint32(config.collateralConfig.heartBeat),
                config.underlyingConfig.priceFeedAddr,
                uint32(config.underlyingConfig.heartBeat),
                config.salt,
                config.marketSymbol
            )
        );
        console.log("Market config written to:", marketFilePath);
    }

    function _getMarketFileName(address collateralAddr, address underlyingAddr, uint256 maturity)
        internal
        view
        returns (string memory)
    {
        return string.concat(
            network,
            "-market-",
            IERC20Metadata(underlyingAddr).symbol(),
            "-",
            IERC20Metadata(collateralAddr).symbol(),
            "@",
            StringHelper.convertTimestampToDateString(maturity, "YYYY-MM-DD"),
            ".json"
        );
    }

    function _createMarketJson(
        TermMaxMarket market,
        MarketConfig memory marketConfig,
        IMintableERC20 ft,
        IMintableERC20 xt,
        IGearingToken gt,
        address collateralAddr,
        IERC20 underlying,
        address collateralPriceFeedAddr,
        uint32 collateralHeartbeat,
        address underlyingPriceFeedAddr,
        uint32 underlyingHeartbeat,
        uint256 salt,
        string memory marketSymbol
    ) internal view returns (string memory) {
        // Create JSON in parts to avoid stack too deep errors
        string memory part1 = _createJsonPart1(
            market,
            collateralAddr,
            collateralPriceFeedAddr,
            underlying,
            underlyingPriceFeedAddr,
            collateralHeartbeat,
            underlyingHeartbeat
        );

        string memory part2 = _createJsonPart2(ft, xt, gt, marketConfig, salt, marketSymbol);

        return string.concat(part1, part2);
    }

    function _createJsonPart1(
        TermMaxMarket market,
        address collateralAddr,
        address collateralPriceFeedAddr,
        IERC20 underlying,
        address underlyingPriceFeedAddr,
        uint32 collateralHeartbeat,
        uint32 underlyingHeartbeat
    ) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                "{\n",
                '  "blockInfo": {\n',
                '    "number": "',
                vm.toString(block.number),
                '",\n',
                '    "timestamp": "',
                vm.toString(block.timestamp),
                '"\n',
                "  },\n",
                '  "market": "',
                vm.toString(address(market)),
                '",\n',
                '  "collateral": {\n',
                '    "address": "',
                vm.toString(collateralAddr),
                '",\n',
                '    "symbol": "',
                IERC20Metadata(collateralAddr).symbol(),
                '",\n',
                '    "priceFeed": "',
                vm.toString(collateralPriceFeedAddr),
                '",\n',
                '    "heartBeat": "',
                vm.toString(collateralHeartbeat),
                '"\n',
                "  },\n",
                '  "underlying": {\n',
                '    "address": "',
                vm.toString(address(underlying)),
                '",\n',
                '    "symbol": "',
                IERC20Metadata(address(underlying)).symbol(),
                '",\n',
                '    "priceFeed": "',
                vm.toString(underlyingPriceFeedAddr),
                '",\n',
                '    "heartBeat": "',
                vm.toString(underlyingHeartbeat),
                '"\n',
                "  },\n"
            )
        );
    }

    function _createJsonPart2(
        IMintableERC20 ft,
        IMintableERC20 xt,
        IGearingToken gt,
        MarketConfig memory marketConfig,
        uint256 salt,
        string memory marketSymbol
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '  "tokens": {\n',
                '    "ft": "',
                vm.toString(address(ft)),
                '",\n',
                '    "xt": "',
                vm.toString(address(xt)),
                '",\n',
                '    "gt": "',
                vm.toString(address(gt)),
                '"\n',
                "  },\n",
                '  "config": {\n',
                '    "marketSymbol": "',
                marketSymbol,
                '",\n',
                '    "treasurer": "',
                vm.toString(marketConfig.treasurer),
                '",\n',
                '    "maturity": "',
                StringHelper.convertTimestampToDateString(marketConfig.maturity, "YYYY-MM-DD"),
                '",\n',
                '    "salt": "',
                vm.toString(salt),
                '",\n',
                '    "fees": {\n',
                '      "lendTakerFeeRatio": "',
                vm.toString(marketConfig.feeConfig.lendTakerFeeRatio),
                '",\n',
                '      "lendMakerFeeRatio": "',
                vm.toString(marketConfig.feeConfig.lendMakerFeeRatio),
                '",\n',
                '      "borrowTakerFeeRatio": "',
                vm.toString(marketConfig.feeConfig.borrowTakerFeeRatio),
                '",\n',
                '      "borrowMakerFeeRatio": "',
                vm.toString(marketConfig.feeConfig.borrowMakerFeeRatio),
                '",\n',
                '      "mintGtFeeRatio": "',
                vm.toString(marketConfig.feeConfig.mintGtFeeRatio),
                '",\n',
                '      "mintGtFeeRef": "',
                vm.toString(marketConfig.feeConfig.mintGtFeeRef),
                '"\n',
                "    }\n",
                "  }\n",
                "}"
            )
        );
    }
}
