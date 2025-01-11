// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../../contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../../contracts/TermMaxMarket.sol";
import {MockERC20} from "../../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../../../contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../../contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "../../../contracts/tokens/IGearingToken.sol";
import {IOracle} from "../../../contracts/oracle/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../../contracts/test/MockSwapAdapter.sol";
import {JsonLoader} from "../../utils/JsonLoader.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../../contracts/test/testnet/FaucetERC20.sol";
import {DeployBase} from "../DeployBase.s.sol";

contract DeloyMarketHolesky is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("HOLESKY_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("HOLESKY_ADMIN_ADDRESS");
    address priceFeedOperatorAddr = vm.envAddress("HOLESKY_PRICE_FEED_OPERATOR_ADDRESS");

    // address config
    address factoryAddr = address(0xD158d15966b6c6802BFD8CB9E5571D4CED0e8510);
    address oracleAddr = address(0xB05F4EF61bAC0b78c49093A9C63aC5aA9443f066);
    address routerAddr = address(0x6c95f1dD21C3da58c8a7280274Ed117aff0DF1A3);
    address faucetAddr = address(0x867BDb6710e831BFD692619376135Dd4B42657Cc);

    address[] devs = [
        address(0x19A736387ea2F42AcAb1BC0FdE15e667e63ea9cC), // Sunny
        address(0x9b1A93b6C9F275FE1720e18331315Ec35484a662), // Mingyu
        address(0x86e59Ec7629b58E1575997B9dF9622a496f0b4Eb), // Garrick
        address(0xE355d5D8aa52EF0FbbD037C4a3C5E6Fd659cf46B) // Aaron
    ];

    function run() public {
        uint256 currentBlockNum = block.number;
        Faucet faucet = Faucet(faucetAddr);
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/holesky.json");
        vm.startBroadcast(deployerPrivateKey);
        TermMaxMarket[] memory markets = deployMarkets(
            factoryAddr,
            oracleAddr,
            routerAddr,
            faucetAddr,
            deployDataPath,
            adminAddr,
            priceFeedOperatorAddr,
            60
        );

        console.log("Faucet token number:", faucet.tokenNum());

        // for (uint i = 0; i < devs.length; i++) {
        //     console.log("Mint faucet tokens to %s", devs[i]);
        //     faucet.devBatchMint(devs[i]);
        // }

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

    function printMarketConfig(Faucet faucet, TermMaxMarket market) public view {
        MarketConfig memory marketConfig = market.config();
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateralAddr, IERC20 underlying) = market
            .tokens();

        Faucet.TokenConfig memory collateralConfig = faucet.getTokenConfig(faucet.getTokenId(collateralAddr));

        Faucet.TokenConfig memory underlyingConfig = faucet.getTokenConfig(faucet.getTokenId(address(underlying)));

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
        console.log("Collateral price feed deployed at:", address(collateralConfig.priceFeedAddr));
        console.log("Underlying price feed deployed at:", address(underlyingConfig.priceFeedAddr));

        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("GT deployed at:", address(gt));

        console.log();

        console.log("Treasurer:", marketConfig.treasurer);
        console.log("Maturity:", marketConfig.maturity);
        console.log("Open Time:", marketConfig.openTime);
        console.log("Lend Taker Fee Ratio:", marketConfig.feeConfig.lendTakerFeeRatio);
        console.log("Lend Maker Fee Ratio:", marketConfig.feeConfig.lendMakerFeeRatio);
        console.log("Borrow Taker Fee Ratio:", marketConfig.feeConfig.borrowTakerFeeRatio);
        console.log("Borrow Maker Fee Ratio:", marketConfig.feeConfig.borrowMakerFeeRatio);
        console.log("Issue FT Fee Ratio:", marketConfig.feeConfig.issueFtFeeRatio);
        console.log("Issue FT Fee Ref:", marketConfig.feeConfig.issueFtFeeRef);
        console.log("Redeem FT Fee Ratio:", marketConfig.feeConfig.redeemFeeRatio);
    }
}
