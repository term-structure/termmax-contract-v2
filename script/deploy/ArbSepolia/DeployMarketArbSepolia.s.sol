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
import {IOracle} from "../../../contracts/core/oracle/IOracle.sol";
import {IGearingToken} from "../../../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../../contracts/test/MockSwapAdapter.sol";
import {JsonLoader} from "../../utils/JsonLoader.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../../contracts/test/testnet/FaucetERC20.sol";
import {DeployBase} from "../DeployBase.s.sol";

contract DeloyMarketArbSepolia is DeployBase {
    uint256 currentBlockNum = block.number;
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");
    address priceFeedOperatorAddr =
        vm.envAddress("ARB_SEPOLIA_PRICE_FEED_OPERATOR_ADDRESS");

    // address config
    address faucetAddr = address(0x7a9ec4cE938837C2bf7B43e7a71DB05CFf90B1FC);
    address factoryAddr = address(0x2A733482A65E2e037491ADA30E8B3547b2Ca95e1);
    address routerAddr = address(0xc3ea773230D7F7Dae97f782d447d54C7B1739Eb2);

    address[] devs = [
        address(0x19A736387ea2F42AcAb1BC0FdE15e667e63ea9cC), // Sunny
        address(0x9b1A93b6C9F275FE1720e18331315Ec35484a662), // Mingyu
        address(0x86e59Ec7629b58E1575997B9dF9622a496f0b4Eb), // Garrick
        address(0xE355d5D8aa52EF0FbbD037C4a3C5E6Fd659cf46B) // Aaron
    ];

    function run() public {
        Faucet faucet = Faucet(faucetAddr);
        string memory deployDataPath = string.concat(
            vm.projectRoot(),
            "/script/deploy/deploydata/arbSepolia.json"
        );
        vm.startBroadcast(deployerPrivateKey);
        TermMaxMarket[] memory markets = deployMarkets(
            factoryAddr,
            routerAddr,
            faucetAddr,
            deployDataPath,
            adminAddr,
            priceFeedOperatorAddr,
            200
        );

        console.log("Faucet token number:", faucet.tokenNum());

        for (uint i = 0; i < devs.length; i++) {
            console.log("Mint faucet tokens to %s", devs[i]);
            faucet.devBatchMint(devs[i]);
        }

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
