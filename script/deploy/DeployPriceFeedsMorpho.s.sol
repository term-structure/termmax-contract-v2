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

        {
            // morpho(gtusdcf): https://app.morpho.org/ethereum/vault/0xc582F04d8a82795aa2Ff9c8bb4c1c889fe7b754e/gauntlet-usdc-frontier
            address gtusdcfVault = 0xc582F04d8a82795aa2Ff9c8bb4c1c889fe7b754e;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd-svr
            // heartBeat: 86400  (24hr)
            address usdcToUsd = 0xfB6471ACD42c91FF265344Ff73E88353521d099F;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface gtusdcfFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, gtusdcfVault));
            (, int256 answer,,,) = gtusdcfFeed.latestRoundData();
            console.log("gtusdcf price feed address", address(gtusdcfFeed));
            console.log("gtusdcf last answer", answer);
        }

        {
            // morpho(MC-wETH): https://app.morpho.org/ethereum/vault/0x701907283a57FF77E255C3f1aAD790466B8CE4ef/index-coop-hyeth
            address mhyETHVault = 0x701907283a57FF77E255C3f1aAD790466B8CE4ef;
            // chainlink(ETH/USD): https://data.chain.link/feeds/ethereum/mainnet/eth-usd
            // heartBeat: 3600 (1hr)
            address wethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            // new price feed heartBeat = max(3600) = 3600 (1hr)
            AggregatorV3Interface mhyETHFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, mhyETHVault));
            (, int256 answer,,,) = mhyETHFeed.latestRoundData();
            console.log("mhyETH price feed address", address(mhyETHFeed));
            console.log("mhyETH last answer", answer);
        }

        {
            // morpho(MC-wETH): https://app.morpho.org/ethereum/vault/0x701907283a57FF77E255C3f1aAD790466B8CE4ef/index-coop-hyeth
            address mhyETHVault = 0x701907283a57FF77E255C3f1aAD790466B8CE4ef;
            // redstone(ETH/USD): https://app.redstone.finance/app/feeds/?search=ETH%2FUSD&page=1&sortBy=popularity&sortDesc=false&perPage=32
            // heartBeat: 86400 (24hr)
            address wethToUsd = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface mhyETHBackupFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, mhyETHVault));
            (, int256 answer,,,) = mhyETHBackupFeed.latestRoundData();
            console.log("mhyETHBackup price feed address", address(mhyETHBackupFeed));
            console.log("mhyETHBackup last answer", answer);
        }

        {
            // morpho(MC_USDCP): https://app.morpho.org/ethereum/vault/0xf1fd8AC6346eC7BC4116Ba7aDc81102B2BC4C52D/mev-capital-usdc-prime
            address mevUsdcPrimeVault = 0xf1fd8AC6346eC7BC4116Ba7aDc81102B2BC4C52D;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd-svr
            // heartBeat: 86400  (24hr)
            address usdcToUsd = 0xfB6471ACD42c91FF265344Ff73E88353521d099F;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface mevUsdcPrimeFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, mevUsdcPrimeVault));
            (, int256 answer,,,) = mevUsdcPrimeFeed.latestRoundData();
            console.log("mevUsdcPrime price feed address", address(mevUsdcPrimeFeed));
            console.log("mevUsdcPrime last answer", answer);
        }

        vm.stopBroadcast();
    }
}
