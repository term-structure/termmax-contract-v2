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
        address slvlUSDFeedAddr;
        {
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            // Coingecko: https://www.coingecko.com/en/coins/staked-level-usd
            address vault = 0x4737D9b4592B40d51e110b94c9C043c6654067Ae;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface slvlUSDFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, vault));
            (, int256 answer,,,) = slvlUSDFeed.latestRoundData();
            slvlUSDFeedAddr = address(slvlUSDFeed);
            console.log("slvlUSD price feed address", address(slvlUSDFeed));
            console.log("slvlUSD last answer", answer);
        }

        {
            // pendle(PT-slvlUSD 25SEP2025): https://app.pendle.finance/trade/markets/0xc88ff954d42d3e11d43b62523b3357847c29377c/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0xC88FF954d42d3e11D43B62523B3357847C29377c;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, slvlUSDFeedAddr)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_slvlUSD_25SEP2025 price feed address", address(ptFeed));
            console.log("pt_slvlUSD_25SEP2025 last answer", answer);
        }

        {
            // pendle(PT-mMEV 31JUL2025): https://app.pendle.finance/trade/markets/0x266728b30c98b24de810e3325adc615486988cb2/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0x266728b30c98B24De810E3325aDC615486988Cb2;
            // custom price feed by themself
            address mMEVToUsd = 0x5f09Aff8B9b1f488B7d1bbaD4D89648579e55d61;
            // new price feed heartBeat = max(5*86400) = 5*86400 (5 days)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, mMEVToUsd)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_mMEV_31JUL2025 price feed address", address(ptFeed));
            console.log("pt_mMEV_31JUL2025 last answer", answer);
        }

        vm.stopBroadcast();
    }
}
