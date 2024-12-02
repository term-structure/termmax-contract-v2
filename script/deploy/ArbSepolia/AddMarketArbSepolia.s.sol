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

contract AddMarketArbSepolia is Script {
    // admin config
    // uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    // address deployerAddr = vm.addr(deployerPrivateKey);
    // address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");
    address priceFeedOperatorAddr =
        vm.envAddress("LOCAL_PRICE_FEED_OPERATOR_ADDRESS");

    uint256 deployerPrivateKey = vm.envUint("LOCAL_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("LOCAL_ADMIN_ADDRESS");

    // address config
    address faucetAddr = address(0x29a79095352a718B3D7Fe84E1F14E9F34A35598e);
    address factoryAddr = address(0x12975173B87F7595EE45dFFb2Ab812ECE596Bf84);
    address routerAddr = address(0x05B4CB126885fb10464fdD12666FEb25E2563B76);

    function run() public {
        Faucet faucet = Faucet(faucetAddr);
        TermMaxFactory factory = TermMaxFactory(factoryAddr);
        TermMaxRouter router = TermMaxRouter(routerAddr);

        string memory deployData = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/deploydata/deployData.json"
            )
        );

        JsonLoader.Config[] memory configs = JsonLoader.getConfigsFromJson(
            deployData
        );

        console.log("Deplyer:", adminAddr);
        console.log("Price Feed Operator:", priceFeedOperatorAddr);
        console.log("");

        for (uint256 i; i < configs.length; i++) {
            console.log("----- Market %d -----", i);
            JsonLoader.Config memory config = configs[i];
            vm.startPrank(adminAddr);
            // deploy underlying & collateral
            (FaucetERC20 collateral, MockPriceFeed collateralPriceFeed) = faucet
                .addToken(
                    config.collateralConfig.name,
                    config.collateralConfig.symbol,
                    config.collateralConfig.decimals,
                    config.collateralConfig.mintAmt
                );

            collateralPriceFeed.updateRoundData(
                MockPriceFeed.RoundData({
                    roundId: 1,
                    answer: config.collateralConfig.initialPrice,
                    startedAt: block.timestamp,
                    updatedAt: block.timestamp,
                    answeredInRound: 1
                })
            );

            (FaucetERC20 underlying, MockPriceFeed underlyingPriceFeed) = faucet
                .addToken(
                    config.underlyingConfig.name,
                    config.underlyingConfig.symbol,
                    config.underlyingConfig.decimals,
                    config.underlyingConfig.mintAmt
                );

            underlyingPriceFeed.updateRoundData(
                MockPriceFeed.RoundData({
                    roundId: 1,
                    answer: config.underlyingConfig.initialPrice,
                    startedAt: block.timestamp,
                    updatedAt: block.timestamp,
                    answeredInRound: 1
                })
            );

            collateralPriceFeed.transferOwnership(priceFeedOperatorAddr);
            underlyingPriceFeed.transferOwnership(priceFeedOperatorAddr);

            MarketConfig memory marketConfig = MarketConfig({
                treasurer: config.marketConfig.treasurer,
                maturity: config.marketConfig.maturity,
                openTime: uint64(vm.getBlockTimestamp() + 60),
                apr: config.marketConfig.apr,
                lsf: config.marketConfig.lsf,
                lendFeeRatio: config.marketConfig.lendFeeRatio,
                minNLendFeeR: config.marketConfig.minNLendFeeR,
                borrowFeeRatio: config.marketConfig.borrowFeeRatio,
                minNBorrowFeeR: config.marketConfig.minNBorrowFeeR,
                redeemFeeRatio: config.marketConfig.redeemFeeRatio,
                issueFtFeeRatio: config.marketConfig.issueFtFeeRatio,
                lockingPercentage: config.marketConfig.lockingPercentage,
                initialLtv: config.marketConfig.initialLtv,
                protocolFeeRatio: config.marketConfig.protocolFeeRatio,
                rewardIsDistributed: false
            });

            // deploy market
            ITermMaxFactory.DeployParams memory params = ITermMaxFactory
                .DeployParams({
                    gtKey: keccak256(
                        bytes(config.collateralConfig.gtKeyIdentifier)
                    ),
                    admin: adminAddr,
                    collateral: address(collateral),
                    underlying: IERC20Metadata(address(underlying)),
                    underlyingOracle: AggregatorV3Interface(
                        address(underlyingPriceFeed)
                    ),
                    liquidationLtv: config.marketConfig.liquidationLtv,
                    maxLtv: config.marketConfig.maxLtv,
                    liquidatable: config.marketConfig.liquidatable,
                    marketConfig: marketConfig,
                    gtInitalParams: abi.encode(address(collateralPriceFeed))
                });
            TermMaxMarket market = TermMaxMarket(factory.createMarket(params));

            router.setMarketWhitelist(address(market), true);

            console.log("Market deployed at:", address(market));
            console.log(
                "Collateral (%s) deployed at: %s",
                IERC20Metadata(collateral).symbol(),
                address(collateral)
            );
            console.log(
                "Collateral price feed deployed at:",
                address(collateralPriceFeed)
            );
            console.log(
                "Underlying (%s) deployed at: %s",
                IERC20Metadata(address(underlying)).symbol(),
                address(underlying)
            );
            console.log(
                "Underlying price feed deployed at:",
                address(underlyingPriceFeed)
            );
            {
                (
                    IMintableERC20 ft,
                    IMintableERC20 xt,
                    IMintableERC20 lpFt,
                    IMintableERC20 lpXt,
                    IGearingToken gt,
                    ,

                ) = market.tokens();

                console.log("FT deployed at:", address(ft));
                console.log("XT deployed at:", address(xt));
                console.log("LPFT deployed at:", address(lpFt));
                console.log("LPXT deployed at:", address(lpXt));
                console.log("GT deployed at:", address(gt));
            }

            console.log("");

            // printMarketConfig(market);

            vm.stopPrank();
        }
    }

    function printMarketConfig(TermMaxMarket market) public view {
        MarketConfig memory marketConfig = market.config();
        console.log("===== Market Info =====");
        console.log("Treasurer:", marketConfig.treasurer);
        console.log("Maturity:", marketConfig.maturity);
        console.log("Open Time:", marketConfig.openTime);
        console.log("Initial APR:", marketConfig.apr);
        console.log("Liquidity Scaling Factor:", marketConfig.lsf);
        console.log("Lending Fee Ratio:", marketConfig.lendFeeRatio);
        console.log(
            "Min Notional Lending Fee Ratio:",
            marketConfig.minNLendFeeR
        );
        console.log("Borrowing Fee Ratio:", marketConfig.borrowFeeRatio);
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
