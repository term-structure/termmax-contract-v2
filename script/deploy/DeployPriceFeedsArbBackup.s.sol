// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceFeedFactory} from "contracts/extensions/PriceFeedFactory.sol";

contract DeployPriceFeedsArb is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ARB_MAINNET_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        PriceFeedFactory priceFeedFactory = new PriceFeedFactory();

        console.log("PriceFeedFactory deployed at", address(priceFeedFactory));
        // pendle deployment: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/deployments/42161-core.json
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        address weEthOracle;

        {
            // redstone(weETH/ETH): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=weETH
            // heartBeat: 86400 (24hr)
            address weEthToEth = 0xA736eAe8805dDeFFba40cAB8c99bCB309dEaBd9B;
            // eOracle(ETH/USD): https://docs.eo.app/docs/eprice/feed-addresses/arbitrum
            // heartBeat: 86400 (24hr)
            address ethToUsd = 0xd68AeF8Ab6D86CeC502e08Faa376297d836FdfA6;
            // new price feed heartBeat = max(86400, 86400) = 86400 (24hr)
            AggregatorV3Interface weEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(weEthToEth, ethToUsd));
            (, int256 answer,,,) = weEthFeed.latestRoundData();
            AggregatorV3Interface weEthFeedCheck = AggregatorV3Interface(0x8f29Df42c617C222Bc2B416AC8a022E85e853276);
            (, int256 answerCheck,,,) = weEthFeedCheck.latestRoundData();
            console.log("weEth price feed address", address(weEthFeed));
            console.log("weEth last answer", answer);
            console.log("weEth last answer check", answerCheck);
            weEthOracle = address(weEthFeed);
        }

        {
            // pendle(PT-weETH 26JUN2025): https://app.pendle.finance/trade/markets/0xbf5e60ddf654085f80dae9dd33ec0e345773e1f8/swap?view=pt&chain=arbitrum&tab=info
            address PT_weETH_26JUN2025_market = 0xBf5E60ddf654085F80DAe9DD33Ec0E345773E1F8;
            // weETH/USD heartBeat: 86400 (24hr)
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, PT_weETH_26JUN2025_market, 900, weEthOracle)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            AggregatorV3Interface ptFeedCheck = AggregatorV3Interface(0x2a2a0e32c54670045256EBcA681887E32e689E97);
            (, int256 answerCheck,,,) = ptFeedCheck.latestRoundData();
            console.log("pt_weETH_26JUN2025 price feed address", address(ptFeed));
            console.log("pt_weETH_26JUN2025 last answer", answer);
            console.log("pt_weETH_26JUN2025 last answer check", answerCheck);
        }

        vm.stopBroadcast();
    }
}
