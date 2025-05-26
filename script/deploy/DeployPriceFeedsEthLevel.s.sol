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
        PriceFeedFactory priceFeedFactory = new PriceFeedFactory();

        console.log("PriceFeedFactory deployed at", address(priceFeedFactory));
        // pendle deployments: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/deployments/1-core.json
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        {
            // pendle(PT-lvlUSD-29MAY2025): https://app.pendle.finance/trade/markets/0xe45d2ce15abba3c67b9ff1e7a69225c855d3da82/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0xE45d2CE15aBbA3c67b9fF1E7A69225C855d3DA82;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, usdcToUsd)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_lvlUSD_29MAY2025 price feed address", address(ptFeed));
            console.log("pt_lvlUSD_29MAY2025 last answer", answer);
        }

        {
            // slvlUSD: https://etherscan.io/address/0x4737D9b4592B40d51e110b94c9C043c6654067Ae#readContract
            address slvlUsd = 0x4737D9b4592B40d51e110b94c9C043c6654067Ae;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface slvlUsdFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, slvlUsd));
            (, int256 answer,,,) = slvlUsdFeed.latestRoundData();
            console.log("slvlUSD price feed address", address(slvlUsdFeed));
            console.log("slvlUSD last answer", answer);
        }

        {
            // morpho(USUALUSDC+): https://app.morpho.org/ethereum/vault/0xd63070114470f685b75B74D60EEc7c1113d33a3D/mev-capital-usual-usdc
            address USUALUSDCPlusVault = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usdcPlusFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, USUALUSDCPlusVault));
            (, int256 answer,,,) = usdcPlusFeed.latestRoundData();
            console.log("USUALUSDC+ price feed address", address(usdcPlusFeed));
            console.log("USUALUSDC+ last answer", answer);
        }

        vm.stopBroadcast();
    }
}
