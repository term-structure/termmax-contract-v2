// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {TermMaxPriceFeedFactory} from "contracts/oracle/priceFeeds/TermMaxPriceFeedFactory.sol";

contract DeployPriceFeedsArb is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        TermMaxPriceFeedFactory priceFeedFactory = new TermMaxPriceFeedFactory();

        console.log("PriceFeedFactory deployed at", address(priceFeedFactory));
        // pendle deployment: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/deployments/42161-core.json
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        address weEthOracle;
        {
            // chainlink(wstETH/ETH): https://data.chain.link/feeds/arbitrum/mainnet/wsteth-eth
            // heartBeat: 86400 (24hr)
            address wstEthToEth = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;
            // chainlink(ETH/USD): https://data.chain.link/feeds/arbitrum/mainnet/eth-usd
            // heartBeat: 86400 (24hr)
            address ethToUsd = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
            address wstEth = 0x5979D7b546E38E414F7E9822514be443A4800529;
            // new price feed heartBeat = max(86400, 86400) = 86400 (24hr)
            AggregatorV3Interface wstEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(wstEthToEth, ethToUsd, wstEth));
            (, int256 answer,,,) = wstEthFeed.latestRoundData();
            console.log("wstEth price feed description", wstEthFeed.description());
            console.log("wstEth price feed address", address(wstEthFeed));
            console.log("wstEth last answer", answer);
        }

        {
            // chainlink(weETH/ETH): https://data.chain.link/feeds/arbitrum/mainnet/weeth-eth
            // heartBeat: 86400 (24hr)
            address weEthToEth = 0xE141425bc1594b8039De6390db1cDaf4397EA22b;
            // chainlink(ETH/USD): https://data.chain.link/feeds/arbitrum/mainnet/eth-usd
            // heartBeat: 86400 (24hr)
            address ethToUsd = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
            // new price feed heartBeat = max(86400, 86400) = 86400 (24hr)
            address weEth = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;
            AggregatorV3Interface weEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(weEthToEth, ethToUsd, weEth));
            (, int256 answer,,,) = weEthFeed.latestRoundData();
            console.log("weEth price feed description", weEthFeed.description());
            console.log("weEth price feed address", address(weEthFeed));
            console.log("weEth last answer", answer);
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
            console.log("pt_weETH_26JUN2025 price feed description", ptFeed.description());
            console.log("pt_weETH_26JUN2025 price feed address", address(ptFeed));
            console.log("pt_weETH_26JUN2025 last answer", answer);
        }

        vm.stopBroadcast();
    }
}
