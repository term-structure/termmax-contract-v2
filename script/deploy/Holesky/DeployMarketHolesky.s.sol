// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/storage/TermMaxStorage.sol";
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

contract DeloyMarketHolesky is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("HOLESKY_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("HOLESKY_ADMIN_ADDRESS");
    address priceFeedOperatorAddr = vm.envAddress("HOLESKY_PRICE_FEED_OPERATOR_ADDRESS");

    address factoryAddr;
    address oracleAddr;
    address routerAddr;
    address faucetAddr;

    function loadAddressConfig() internal {
        string memory deploymentPath = string.concat(vm.projectRoot(), "/deployments/eth-holesky/eth-holesky-core.json");
        string memory json = vm.readFile(deploymentPath);

        factoryAddr = vm.parseJsonAddress(json, ".contracts.factory");
        oracleAddr = vm.parseJsonAddress(json, ".contracts.oracleAggregator");
        routerAddr = vm.parseJsonAddress(json, ".contracts.router");
        faucetAddr = vm.parseJsonAddress(json, ".contracts.faucet");

        console.log("Loaded addresses from deployment file:");
        console.log("  Factory:", factoryAddr);
        console.log("  Oracle:", oracleAddr);
        console.log("  Router:", routerAddr);
        console.log("  Faucet:", faucetAddr);
    }

    function run() public {
        loadAddressConfig();

        uint256 currentBlockNum = block.number;
        Faucet faucet = Faucet(faucetAddr);
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/holesky.json");
        vm.startBroadcast(deployerPrivateKey);
        (TermMaxMarket[] memory markets, JsonLoader.Config[] memory configs) = deployMarkets(
            factoryAddr, oracleAddr, routerAddr, faucetAddr, deployDataPath, adminAddr, priceFeedOperatorAddr
        );

        console.log("Faucet token number:", faucet.tokenNum());

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Address Info =====");
        console.log("Deplyer:", deployerAddr);
        console.log("Price Feed Operator:", priceFeedOperatorAddr);
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");

        for (uint256 i = 0; i < markets.length; i++) {
            console.log("===== Market Info - %d =====", i);
            printMarketConfig(faucet, markets[i], configs[i].salt);
            console.log("");
        }
    }

    function printMarketConfig(Faucet faucet, TermMaxMarket market, uint256 salt) public {
        MarketConfig memory marketConfig = market.config();
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateralAddr, IERC20 underlying) =
            market.tokens();

        Faucet.TokenConfig memory collateralConfig = faucet.getTokenConfig(faucet.getTokenId(collateralAddr));
        Faucet.TokenConfig memory underlyingConfig = faucet.getTokenConfig(faucet.getTokenId(address(underlying)));

        console.log("Market deployed at:", address(market));
        console.log("Collateral (%s) deployed at: %s", IERC20Metadata(collateralAddr).symbol(), address(collateralAddr));
        console.log(
            "Underlying (%s) deployed at: %s", IERC20Metadata(address(underlying)).symbol(), address(underlying)
        );
        console.log("Collateral price feed deployed at:", address(collateralConfig.priceFeedAddr));
        console.log("Underlying price feed deployed at:", address(underlyingConfig.priceFeedAddr));

        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("GT deployed at:", address(gt));

        console.log();

        console.log("Treasurer:", marketConfig.treasurer);
        console.log("Maturity:", marketConfig.maturity);
        console.log("Salt:", salt);
        console.log("Lend Taker Fee Ratio:", marketConfig.feeConfig.lendTakerFeeRatio);
        console.log("Lend Maker Fee Ratio:", marketConfig.feeConfig.lendMakerFeeRatio);
        console.log("Borrow Taker Fee Ratio:", marketConfig.feeConfig.borrowTakerFeeRatio);
        console.log("Borrow Maker Fee Ratio:", marketConfig.feeConfig.borrowMakerFeeRatio);
        console.log("Issue FT Fee Ratio:", marketConfig.feeConfig.issueGtFeeRatio);
        console.log("Issue FT Fee Ref:", marketConfig.feeConfig.issueFtFeeRef);

        // Write market config to JSON file
        string memory marketFileName = _getMarketFileName(collateralAddr, address(underlying), marketConfig.maturity);
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/eth-holesky");
        if (!vm.exists(deploymentsDir)) {
            vm.createDir(deploymentsDir, true);
        }

        string memory marketFilePath = string.concat(deploymentsDir, "/", marketFileName);
        vm.writeFile(
            marketFilePath,
            _createMarketJson(
                market, marketConfig, ft, xt, gt, collateralAddr, underlying, collateralConfig, underlyingConfig, salt
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
            "eth-holesky-market-",
            IERC20Metadata(collateralAddr).symbol(),
            "-",
            IERC20Metadata(underlyingAddr).symbol(),
            "@",
            vm.toString(maturity),
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
        Faucet.TokenConfig memory collateralConfig,
        Faucet.TokenConfig memory underlyingConfig,
        uint256 salt
    ) internal view returns (string memory) {
        // Create JSON in parts to avoid stack too deep errors
        string memory part1 = _createJsonPart1(market, collateralAddr, collateralConfig, underlying, underlyingConfig);

        string memory part2 = _createJsonPart2(ft, xt, gt, marketConfig, salt);

        return string.concat(part1, part2);
    }

    function _createJsonPart1(
        TermMaxMarket market,
        address collateralAddr,
        Faucet.TokenConfig memory collateralConfig,
        IERC20 underlying,
        Faucet.TokenConfig memory underlyingConfig
    ) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                "{\n",
                '  "timestamp": "',
                vm.toString(block.timestamp),
                '",\n',
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
                vm.toString(address(collateralConfig.priceFeedAddr)),
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
                vm.toString(address(underlyingConfig.priceFeedAddr)),
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
        uint256 salt
    ) internal view returns (string memory) {
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
                '    "treasurer": "',
                vm.toString(marketConfig.treasurer),
                '",\n',
                '    "maturity": "',
                vm.toString(marketConfig.maturity),
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
                '      "issueGtFeeRatio": "',
                vm.toString(marketConfig.feeConfig.issueGtFeeRatio),
                '",\n',
                '      "issueFtFeeRef": "',
                vm.toString(marketConfig.feeConfig.issueFtFeeRef),
                '"\n',
                "    }\n",
                "  }\n",
                "}"
            )
        );
    }
}
