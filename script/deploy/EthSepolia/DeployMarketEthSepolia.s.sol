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
import {IGearingToken, AggregatorV3Interface} from "../../../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../../contracts/test/MockSwapAdapter.sol";
import {JsonLoader} from "../../utils/JsonLoader.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../../contracts/test/testnet/FaucetERC20.sol";
import {DeployBase} from "../DeployBase.s.sol";

contract DeloyMarketEthSepolia is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ETH_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ETH_SEPOLIA_ADMIN_ADDRESS");
    address priceFeedOperatorAddr =
        vm.envAddress("ETH_SEPOLIA_PRICE_FEED_OPERATOR_ADDRESS");

    // address config
    address faucetAddr = address(0xDE467b4b52A9C159dEd38BB68D304F049bA187E4);
    address factoryAddr = address(0x6e0d016ac48a79a642D4Bc67289d12F712C0A6e2);
    address routerAddr = address(0x13bA0534926c5bA1516A7e488B177C0cF57e440e);

    function run() public {
        Faucet faucet = Faucet(faucetAddr);
        string memory deployDataPath = string.concat(
            vm.projectRoot(),
            "/script/deploy/deploydata/ethSepolia.json"
        );
        vm.startBroadcast(deployerPrivateKey);
        TermMaxMarket[] memory markets = deployMarkets(
            factoryAddr,
            routerAddr,
            faucetAddr,
            deployDataPath,
            adminAddr,
            priceFeedOperatorAddr,
            600
        );
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Address Info =====");
        console.log("Deplyer:", deployerAddr);
        console.log("Price Feed Operator:", priceFeedOperatorAddr);
        console.log("");

        for (uint i = 0; i < markets.length; i++) {
            console.log("===== Market Info - %d =====", i);
            printMarketConfig(faucet, markets[i]);
            console.log("");
        }
    }

    function printMarketConfig(
        Faucet faucet,
        TermMaxMarket market
    ) public view {
        MarketConfig memory marketConfig = market.config();
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingToken gt,
            address collateralAddr,
            IERC20 underlying
        ) = market.tokens();

        Faucet.TokenConfig memory collateralConfig = faucet.getTokenConfig(
            faucet.getTokenId(collateralAddr)
        );

        Faucet.TokenConfig memory underlyingConfig = faucet.getTokenConfig(
            faucet.getTokenId(address(underlying))
        );

        console.log("Market deployed at:", address(market));
        console.log(
            "Collateral (%s) deployed at: %s",
            IERC20Metadata(collateralAddr).symbol(),
            address(collateralAddr)
        );
        console.log(
            "Underlying (%s) deployed at: %s",
            IERC20Metadata(address(underlying)).symbol(),
            address(underlying)
        );
        console.log(
            "Collateral price feed deployed at:",
            address(collateralConfig.priceFeedAddr)
        );
        console.log(
            "Underlying price feed deployed at:",
            address(underlyingConfig.priceFeedAddr)
        );

        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("LPFT deployed at:", address(lpFt));
        console.log("LPXT deployed at:", address(lpXt));
        console.log("GT deployed at:", address(gt));

        console.log();

        console.log("Treasurer:", marketConfig.treasurer);
        console.log("Maturity:", marketConfig.maturity);
        console.log("Open Time:", marketConfig.openTime);
        console.log("Initial APR:", marketConfig.apr);
        console.log("Liquidity Scaling Factor:", marketConfig.lsf);
        console.log("Lending Fee Ratio:", marketConfig.lendFeeRatio);
        console.log("Borrowing Fee Ratio:", marketConfig.borrowFeeRatio);
        console.log(
            "Min Notional Lending Fee Ratio:",
            marketConfig.minNLendFeeR
        );
        console.log(
            "Min Notional Borrowing Fee Ratio:",
            marketConfig.minNBorrowFeeR
        );
        console.log("Redeem Fee Ratio:", marketConfig.redeemFeeRatio);
        console.log("Issue FT Fee Ratio:", marketConfig.issueFtFeeRatio);
        console.log("Protocol Fee Ratio:", marketConfig.protocolFeeRatio);
        console.log("Locking Percentage:", marketConfig.lockingPercentage);
        console.log("Initial LTV:", marketConfig.initialLtv);
        console.log("Reward Is Distributed:", marketConfig.rewardIsDistributed);
    }
}
