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
        address pufferEthOracle;
        {
            // redstone(pufETH/ETH): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=pufETH
            // heartBeat: 86400 (24hr)
            address pufferEthToEth = 0x76A495b0bFfb53ef3F0E94ef0763e03cE410835C;
            // redstone(ETH/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=ETH%2FUSD
            // heartBeat: 86400 (24hr)
            address ethToUsd = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
            // new price feed heartBeat = max(86400, 86400) = 86400 (24hr)
            AggregatorV3Interface pufferEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(pufferEthToEth, ethToUsd));
            (, int256 answer,,,) = pufferEthFeed.latestRoundData();
            // compare with primary feed: 0xB3ae8A16CF827d193Ae51a92fd2630e6839F5761
            AggregatorV3Interface pufferEthFeedCheck = AggregatorV3Interface(0xB3ae8A16CF827d193Ae51a92fd2630e6839F5761);
            (, int256 answerCheck,,,) = pufferEthFeedCheck.latestRoundData();
            console.log("pufferEth backup price feed address", address(pufferEthFeed));
            console.log("pufferEth last answer", answer);
            console.log("pufferEth last answer check", answerCheck);
            pufferEthOracle = address(pufferEthFeed);
        }

        {
            // pendle(PT-sUSDe 29MAY2025): https://app.pendle.finance/trade/markets/0xb162b764044697cf03617c2efbcb1f42e31e4766/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            // redstone(sUSDe/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=sUSDe%2FUSD
            // heartBeat: 86400 (24hr)
            address susdeToUsd = 0xb99D174ED06c83588Af997c8859F93E83dD4733f;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, susdeToUsd)
            );
            // compared with primary feed: 0x8f29Df42c617C222Bc2B416AC8a022E85e853276
            AggregatorV3Interface ptFeedCheck = AggregatorV3Interface(0x8f29Df42c617C222Bc2B416AC8a022E85e853276);
            (, int256 answerCheck,,,) = ptFeedCheck.latestRoundData();
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_sUsde_29MAY2025 backup price feed address", address(ptFeed));
            console.log("pt_sUsde_29MAY2025 last answer", answer);
            console.log("pt_sUsde_29MAY2025 last answer check", answerCheck);
        }

        {
            // morpho(MC-wETH): https://app.morpho.org/ethereum/vault/0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8/mev-capital-weth
            address MCwETHVault = 0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8;
            // redstone(ETH/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=ETH%2FUSD
            // heartBeat: 86400 (24hr)
            address wethToUsd = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface wethFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, MCwETHVault));
            // compared with primary feed: 0xF1D1c1e387820c2eFDB9B863960FaA5d035C2006
            AggregatorV3Interface wethFeedCheck = AggregatorV3Interface(0xF1D1c1e387820c2eFDB9B863960FaA5d035C2006);
            (, int256 answerCheck,,,) = wethFeedCheck.latestRoundData();
            (, int256 answer,,,) = wethFeed.latestRoundData();
            console.log("MCwETH backup price feed address", address(wethFeed));
            console.log("MCwETH last answer", answer);
            console.log("MCwETH last answer check", answerCheck);
        }

        {
            // morpho(gtWETH): https://app.morpho.org/ethereum/vault/0x2371e134e3455e0593363cBF89d3b6cf53740618/gauntlet-weth-prime
            address gtWETHVault = 0x2371e134e3455e0593363cBF89d3b6cf53740618;
            // redstone(ETH/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=ETH%2FUSD
            // heartBeat: 86400 (24hr)
            address wethToUsd = 0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface gtWETHFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, gtWETHVault));
            // compared with primary feed: 0xdc0115fe09600FeDa15D317cCa3D2f21F389036d
            AggregatorV3Interface gtWETHFeedCheck = AggregatorV3Interface(0xdc0115fe09600FeDa15D317cCa3D2f21F389036d);
            (, int256 answerCheck,,,) = gtWETHFeedCheck.latestRoundData();
            (, int256 answer,,,) = gtWETHFeed.latestRoundData();
            console.log("gtWETH backup price feed address", address(gtWETHFeed));
            console.log("gtWETH last answer", answer);
            console.log("gtWETH last answer check", answerCheck);
        }

        {
            // pendle(PT-pufETH 26JUN2025): https://app.pendle.finance/trade/markets/0x58612beb0e8a126735b19bb222cbc7fc2c162d2a/swap?view=pt&chain=ethereum&tab=info
            address PT_pufETH_26JUN2025_market = 0x58612beB0e8a126735b19BB222cbC7fC2C162D2a;
            // pufETH/USD heartBeat: 86400 (24hr)
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(
                    pendlePYLpOracle, PT_pufETH_26JUN2025_market, 900, pufferEthOracle
                )
            );
            // compared with primary feed: 0x5a27314e6D35B6fFCBaE6B3eb030e7Faf7EF34F1
            AggregatorV3Interface ptFeedCheck = AggregatorV3Interface(0x5a27314e6D35B6fFCBaE6B3eb030e7Faf7EF34F1);
            (, int256 answerCheck,,,) = ptFeedCheck.latestRoundData();
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_pufETH_26JUN2025 backup price feed address", address(ptFeed));
            console.log("pt_pufETH_26JUN2025 last answer", answer);
            console.log("pt_pufETH_26JUN2025 last answer check", answerCheck);
        }

        {
            // etherscan(eUSDe): https://etherscan.io/token/0x90d2af7d622ca3141efa4d8f1f24d86e5974cc8f#readContract
            address eUSDeVault = 0x90D2af7d622ca3141efA4d8f1F24d86E5974Cc8F;
            // redstone(USDe/USD): https://app.redstone.finance/app/feeds/?page=1&sortBy=popularity&sortDesc=false&perPage=64&search=USDe%2FUSD
            // heartBeat: 86400 (24hr)
            address usdeToUsd = 0xbC5FBcf58CeAEa19D523aBc76515b9AEFb5cfd58;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usdeFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdeToUsd, eUSDeVault));
            // compared with primary feed: 0xB6549635409Ae9c0eeBB71B3F904cB004F2D97D3
            AggregatorV3Interface usdeFeedCheck = AggregatorV3Interface(0xB6549635409Ae9c0eeBB71B3F904cB004F2D97D3);
            (, int256 answerCheck,,,) = usdeFeedCheck.latestRoundData();
            (, int256 answer,,,) = usdeFeed.latestRoundData();
            console.log("eUSDe backup price feed address", address(usdeFeed));
            console.log("eUSDe last answer", answer);
            console.log("eUSDe last answer check", answerCheck);
        }

        {
            // chainlink(weETH/ETH): https://data.chain.link/feeds/ethereum/mainnet/weeth-eth
            // heartBeat: 86400 (24hr)
            address weEthToEth = 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22;
            // chainlink(ETH/USD): https://data.chain.link/feeds/ethereum/mainnet/eth-usd
            // heartBeat: 3600 (1hr)
            address ethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            // new price feed heartBeat = max(3600, 86400) = 86400 (24hr)
            AggregatorV3Interface weEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(weEthToEth, ethToUsd));
            (, int256 answer,,,) = weEthFeed.latestRoundData();
            // compare with primary feed: 0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136
            AggregatorV3Interface weEthFeedCheck = AggregatorV3Interface(0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136);
            (, int256 answerCheck,,,) = weEthFeedCheck.latestRoundData();
            console.log("weEth backup price feed address", address(weEthFeed));
            console.log("weEth last answer", answer);
            console.log("weEth last answer check", answerCheck);
        }

        vm.stopBroadcast();
    }
}
