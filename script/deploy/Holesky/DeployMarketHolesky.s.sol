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

    // address config
    address factoryAddr = address(0x4e45b67f9A6711C39d04052F766fA2E44d8bDfa5);
    address oracleAddr = address(0x70207A48A28Fcd5111762F570C83c0714fDE7443);
    address routerAddr = address(0xbFccC3c7F739d4aE7CCf680b3fafcFB5Bdc4f842);
    address faucetAddr = address(0xb927B74d5D9c3985D4DCdd62CbffEc66CF527fAa);

    function run() public {
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

    function printMarketConfig(Faucet faucet, TermMaxMarket market, uint256 salt) public view {
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
        console.log("Issue FT Fee Ratio:", marketConfig.feeConfig.issueFtFeeRatio);
        console.log("Issue FT Fee Ref:", marketConfig.feeConfig.issueFtFeeRef);
        console.log("Redeem FT Fee Ratio:", marketConfig.feeConfig.redeemFeeRatio);
    }
}
