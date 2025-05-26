// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceFeedFactory} from "contracts/extensions/PriceFeedFactory.sol";

contract DeployPriceFeeds is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ETH_MAINNET_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address priceFeedFactoryAddress = 0xcac930B240163fDB71b74514E8FAA113ec0dA844;
        PriceFeedFactory priceFeedFactory = PriceFeedFactory(priceFeedFactoryAddress);

        console.log("PriceFeedFactory deployed at", address(priceFeedFactory));
        // pendle deployments: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/deployments/1-core.json
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;

        {
            // pendle(PT-eUSDE-14AUG2025): https://app.pendle.finance/trade/markets/0xe93b4a93e80bd3065b290394264af5d82422ee70/swap?view=pt&chain=ethereum&chart=apy&tab=info
            address pt_market = 0xE93B4A93e80BD3065B290394264af5d82422ee70;
            // eUSDe primary price feed: https://docs.ts.finance/technical-details/oracles
            // heartBeat: 86400 (24hr)
            address eUSDeToUsdPrimary = 0xB6549635409Ae9c0eeBB71B3F904cB004F2D97D3;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeedPrimary = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, eUSDeToUsdPrimary)
            );
            (, int256 answerPrimary,,,) = ptFeedPrimary.latestRoundData();
            console.log("PT-eUSDE-14AUG2025 primary price feed address", address(ptFeedPrimary));
            console.log("PT-eUSDE-14AUG2025 primary last answer", answerPrimary);

            // eUSDe secondary price feed: https://docs.ts.finance/technical-details/oracles
            // heartBeat: 86400 (24hr)
            address eUSDeToUsdSecondary = 0x6B09d473dB784D840E307Cb3Da63CbA79D300CAc;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeedSecondary = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, eUSDeToUsdSecondary)
            );
            (, int256 answerSecondary,,,) = ptFeedSecondary.latestRoundData();
            console.log("PT-eUSDE-14AUG2025 secondary price feed address", address(ptFeedSecondary));
            console.log("PT-eUSDE-14AUG2025 secondary last answer", answerSecondary);
        }

        AggregatorV3Interface lbtcFeedPrimary;
        AggregatorV3Interface lbtcFeedSecondary;
        {
            // chainlink(LBTC/BTC): https://data.chain.link/feeds/ethereum/mainnet/lbtc-btc
            // heartBeat: 86400 (24hr)
            address lbtcToBtcChainlink = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;
            // chainlink(BTC/USD): https://data.chain.link/feeds/ethereum/mainnet/btc-usd
            // heartBeat: 3600 (1hr)
            address btcToUsdChainlink = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
            // new price feed heartBeat = max(3600, 86400) = 86400 (24hr)
            lbtcFeedPrimary =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(lbtcToBtcChainlink, btcToUsdChainlink));
            (, int256 answerPrimary,,,) = lbtcFeedPrimary.latestRoundData();
            console.log("lbtc primary price feed address", address(lbtcFeedPrimary));
            console.log("lbtc primary last answer", answerPrimary);

            // redstone(LBTC/BTC): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=32&search=LBTC
            // heartBeat: 86400 (24hr)
            address lbtcToBtcRedstone = 0xb415eAA355D8440ac7eCB602D3fb67ccC1f0bc81;
            // redstone(BTC/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=32&search=BTC
            // heartBeat: 86400 (24hr)
            address btcToUsdRedstone = 0xAB7f623fb2F6fea6601D4350FA0E2290663C28Fc;
            // new price feed heartBeat = max(86400, 86400) = 86400 (24hr)
            lbtcFeedSecondary =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(lbtcToBtcRedstone, btcToUsdRedstone));
            (, int256 answerSecondary,,,) = lbtcFeedSecondary.latestRoundData();
            console.log("lbtc secondary price feed address", address(lbtcFeedSecondary));
            console.log("lbtc secondary last answer", answerSecondary);
        }

        {
            // pendle(PT-LBTC-26JUN2025): https://app.pendle.finance/trade/markets/0x931f7ea0c31c14914a452d341bc5cb5d996be71d/swap?view=pt&chain=ethereum&chart=apy&tab=info
            address pt_market = 0x931F7eA0c31c14914a452d341bc5Cb5d996BE71d;
            // LBTC primary price feed: deployed in the same script
            // heartBeat: 86400 (24hr)
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeedPrimary = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, address(lbtcFeedPrimary))
            );
            (, int256 answerPrimary,,,) = ptFeedPrimary.latestRoundData();
            console.log("PT-LBTC-26JUN2025 primary price feed address", address(ptFeedPrimary));
            console.log("PT-LBTC-26JUN2025 primary last answer", answerPrimary);

            // LBTC secondary price feed: deployed in the same script
            // heartBeat: 86400 (24hr)
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeedSecondary = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, address(lbtcFeedSecondary))
            );
            (, int256 answerSecondary,,,) = ptFeedSecondary.latestRoundData();
            console.log("PT-LBTC-26JUN2025 secondary price feed address", address(ptFeedSecondary));
            console.log("PT-LBTC-26JUN2025 secondary last answer", answerSecondary);
        }

        {
            // chainlink(ETH/USD): https://data.chain.link/feeds/ethereum/mainnet/eth-usd
            // heartBeat: 3600 (1hr)
            address ethToUsdChainlink = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            // YieldNest: https://docs.yieldnest.finance/protocol-design/max-lrts/yneth-max-ynethx
            address vault = 0x657d9ABA1DBb59e53f9F3eCAA878447dCfC96dCb;
            // new price feed heartBeat = max(3600) = 3600 (24hr)
            AggregatorV3Interface ynEthxPriceFeedPrimary =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(ethToUsdChainlink, vault));
            (, int256 answerPrimary,,,) = ynEthxPriceFeedPrimary.latestRoundData();
            console.log("ynEthx primary price feed address", address(ynEthxPriceFeedPrimary));
            console.log("ynEthx primary last answer", answerPrimary);

            // redstone(ETH/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=32&search=ETH%2FUSD
            // heartBeat: 86400 (24hr)
            address ethToUsdRedstone = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ynEthxPriceFeedSecondary =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(ethToUsdRedstone, vault));
            (, int256 answerSecondary,,,) = ynEthxPriceFeedSecondary.latestRoundData();
            console.log("ynEthx secondary price feed address", address(ynEthxPriceFeedSecondary));
            console.log("ynEthx secondary last answer", answerSecondary);
        }

        {
            // pendle(PT-USDS-14AUG2025): https://app.pendle.finance/trade/markets/0xdace1121e10500e9e29d071f01593fd76b000f08/swap?view=pt&chain=ethereum&chart=apy&tab=info
            address pt_market = 0xdacE1121e10500e9e29d071F01593fD76B000f08;
            // chainlink(USDS/USD): https://data.chain.link/feeds/ethereum/mainnet/usds-usd
            address usdsToUsdChainlink = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;
            // heartBeat: 86400 (24hr)
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeedPrimary = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, usdsToUsdChainlink)
            );
            (, int256 answerPrimary,,,) = ptFeedPrimary.latestRoundData();
            console.log("PT-USDS-14AUG2025 primary price feed address", address(ptFeedPrimary));
            console.log("PT-USDS-14AUG2025 primary last answer", answerPrimary);
        }

        vm.stopBroadcast();
    }
}
