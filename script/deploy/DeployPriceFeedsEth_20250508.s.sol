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
            // pendle(PT-sUSDe 31JUL2025): https://app.pendle.finance/trade/markets/0x4339ffe2b7592dc783ed13cce310531ab366deac/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac;
            // chainlink(sUSDe/USD): https://data.chain.link/feeds/ethereum/mainnet/susde-usd
            // heartBeat: 86400 (24hr)
            address susdeToUsd = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, susdeToUsd)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_sUsde_31JUL2025 price feed address", address(ptFeed));
            console.log("pt_sUsde_31JUL2025 last answer", answer);
        }
        {
            // pendle(PT-lvlUSD-25SEP2025): https://app.pendle.finance/trade/markets/0x461bc2ac3f80801bc11b0f20d63b73fef60c8076/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0x461bc2ac3f80801BC11B0F20d63B73feF60C8076;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, usdcToUsd)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_lvlUSD_25SEP2025 price feed address", address(ptFeed));
            console.log("pt_lvlUSD_25SEP2025 last answer", answer);
        }
        address cUSDOToUsdFeed;
        {
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            address cUSDO = 0xaD55aebc9b8c03FC43cd9f62260391c13c23e7c0;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface cusdoFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, cUSDO));
            cUSDOToUsdFeed = address(cusdoFeed);
            (, int256 answer,,,) = cusdoFeed.latestRoundData();
            console.log("cUSDO price feed address", address(cusdoFeed));
            console.log("cUSDO last answer", answer);
        }
        {
            // pendle(PT-cUSDO-19JUN2025): https://app.pendle.finance/trade/markets/0xa77c0de4d26b7c97d1d42abd6733201206122e25/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0xA77c0DE4d26B7C97D1D42ABD6733201206122E25;
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, cUSDOToUsdFeed)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_cUSDO_19JUN2025 price feed address", address(ptFeed));
            console.log("pt_cUSDO_19JUN2025 last answer", answer);
        }
        address wstUsrToUsdFeed;
        {
            // chainlink(USR/USD): https://data.chain.link/feeds/ethereum/mainnet/usr-usd
            // heartBeat: 86400 (24hr)
            address usrToUsd = 0x34ad75691e25A8E9b681AAA85dbeB7ef6561B42c;
            address wstUsr = 0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface wstUsrFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usrToUsd, wstUsr));
            wstUsrToUsdFeed = address(wstUsrFeed);
            (, int256 answer,,,) = wstUsrFeed.latestRoundData();
            console.log("wstUsr price feed address", address(wstUsrFeed));
            console.log("wstUsr last answer", answer);
        }
        {
            // pendle(PT-wstUSR-25SEP2025): https://app.pendle.finance/trade/markets/0x09fa04aac9c6d1c6131352ee950cd67ecc6d4fb9/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0x09fA04Aac9c6d1c6131352EE950CD67ecC6d4fB9;
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, wstUsrToUsdFeed)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_wstUSR_25SEP2025 price feed address", address(ptFeed));
            console.log("pt_wstUSR_25SEP2025 last answer", answer);
        }

        vm.stopBroadcast();
    }
}
