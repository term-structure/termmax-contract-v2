// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {TermMaxPriceFeedFactory} from "contracts/factory/TermMaxPriceFeedFactory.sol";

contract DeployPriceFeeds is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ETH_MAINNET_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        TermMaxPriceFeedFactory priceFeedFactory = new TermMaxPriceFeedFactory();

        console.log("PriceFeedFactory deployed at", address(priceFeedFactory));
        // pendle deployments: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/deployments/1-core.json
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        address pufferEthOracle;
        {
            // chainlink(pufETH/ETH): https://data.chain.link/feeds/ethereum/mainnet/pufeth-eth
            // heartBeat: 86400 (24hr)
            address pufferEthToEth = 0xDe3f7Dd92C4701BCf59F47235bCb61e727c45f80;
            // chainlink(ETH/USD): https://data.chain.link/feeds/ethereum/mainnet/eth-usd
            // heartBeat: 3600 (1hr)
            address ethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            address pufETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
            // new price feed heartBeat = max(3600, 86400) = 86400 (24hr)
            AggregatorV3Interface pufferEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(pufferEthToEth, ethToUsd, pufETH));
            (, int256 answer,,,) = pufferEthFeed.latestRoundData();
            console.log("pufferEth price feed description", pufferEthFeed.description());
            console.log("pufferEth price feed address", address(pufferEthFeed));
            console.log("pufferEth last answer", answer);
            pufferEthOracle = address(pufferEthFeed);
        }

        {
            // pendle(PT-sUSDe 29MAY2025): https://app.pendle.finance/trade/markets/0xb162b764044697cf03617c2efbcb1f42e31e4766/swap?view=pt&chain=ethereum&tab=info
            address pt_market = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            // chainlink(sUSDe/USD): https://data.chain.link/feeds/ethereum/mainnet/susde-usd
            // heartBeat: 86400 (24hr)
            address susdeToUsd = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, susdeToUsd)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_sUsde_29MAY2025 price feed description", ptFeed.description());
            console.log("pt_sUsde_29MAY2025 price feed address", address(ptFeed));
            console.log("pt_sUsde_29MAY2025 last answer", answer);
        }

        {
            // morpho(USUALUSDC+): https://app.morpho.org/ethereum/vault/0xd63070114470f685b75B74D60EEc7c1113d33a3D/mev-capital-usual-usdc
            address USUALUSDCPlusVault = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd-svr
            // heartBeat: 86400  (24hr)
            address usdcToUsd = 0xfB6471ACD42c91FF265344Ff73E88353521d099F;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usdcPlusFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, USUALUSDCPlusVault));
            (, int256 answer,,,) = usdcPlusFeed.latestRoundData();
            console.log("USUALUSDC+ price feed description", usdcPlusFeed.description());
            console.log("USUALUSDC+ price feed address", address(usdcPlusFeed));
            console.log("USUALUSDC+ last answer", answer);
        }

        {
            // morpho(MC-wETH): https://app.morpho.org/ethereum/vault/0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8/mev-capital-weth
            address MCwETHVault = 0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8;
            // chainlink(ETH/USD): https://data.chain.link/feeds/ethereum/mainnet/eth-usd
            // heartBeat: 3600 (1hr)
            address wethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            // new price feed heartBeat = max(3600) = 3600 (1hr)
            AggregatorV3Interface wethFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, MCwETHVault));
            (, int256 answer,,,) = wethFeed.latestRoundData();
            console.log("MCwETH price feed description", wethFeed.description());
            console.log("MCwETH price feed address", address(wethFeed));
            console.log("MCwETH last answer", answer);
        }

        {
            // morpho(gtWETH): https://app.morpho.org/ethereum/vault/0x2371e134e3455e0593363cBF89d3b6cf53740618/gauntlet-weth-prime
            address gtWETHVault = 0x2371e134e3455e0593363cBF89d3b6cf53740618;
            // chainlink(ETH/USD): https://data.chain.link/feeds/ethereum/mainnet/eth-usd
            // heartBeat: 3600 (1hr)
            address wethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            // new price feed heartBeat = max(3600) = 3600 (1hr)
            AggregatorV3Interface gtWETHFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, gtWETHVault));
            (, int256 answer,,,) = gtWETHFeed.latestRoundData();
            console.log("gtWETH price feed description", gtWETHFeed.description());
            console.log("gtWETH price feed address", address(gtWETHFeed));
            console.log("gtWETH last answer", answer);
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
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_pufETH_26JUN2025 price feed description", ptFeed.description());
            console.log("pt_pufETH_26JUN2025 price feed address", address(ptFeed));
            console.log("pt_pufETH_26JUN2025 last answer", answer);
        }

        {
            // etherscan(eUSDe): https://etherscan.io/token/0x90d2af7d622ca3141efa4d8f1f24d86e5974cc8f#readContract
            address eUSDeVault = 0x90D2af7d622ca3141efA4d8f1F24d86E5974Cc8F;
            // chainlink(eUSDe/USD): https://data.chain.link/feeds/ethereum/mainnet/usde-usd
            // heartBeat: 86400 (24hr)
            address usdeToUsd = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usdeFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdeToUsd, eUSDeVault));
            (, int256 answer,,,) = usdeFeed.latestRoundData();
            console.log("eUSDe price feed description", usdeFeed.description());
            console.log("eUSDe price feed address", address(usdeFeed));
            console.log("eUSDe last answer", answer);
        }

        {
            // pendle(PT-USD0PlusPlus 26JUN2025): https://app.pendle.finance/trade/markets/0x048680f64d6dff1748ba6d9a01f578433787e24b/swap?view=pt&chain=ethereum&tab=info
            address PT_USD0PlusPlus_26JUN2025_market = 0x048680F64d6DFf1748ba6D9a01F578433787e24B;
            // Usual Docs: https://tech.usual.money/smart-contracts/contract-deployments
            //! heartBeat: 86400 (24hr) not sure
            address usd0PlusPlusToUsd = 0xFC9e30Cf89f8A00dba3D34edf8b65BCDAdeCC1cB;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usd0PlusPlusFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(
                    pendlePYLpOracle, PT_USD0PlusPlus_26JUN2025_market, 900, usd0PlusPlusToUsd
                )
            );
            (, int256 answer,,,) = usd0PlusPlusFeed.latestRoundData();
            console.log("PT_USD0PlusPlus_26JUN2025 price feed description", usd0PlusPlusFeed.description());
            console.log("PT_USD0PlusPlus_26JUN2025_market price feed address", address(usd0PlusPlusFeed));
            console.log("PT_USD0PlusPlus_26JUN2025_market last answer", answer);
        }

        {
            // UpShift USDC(upUSDC): https://app.upshift.finance/pools/1/0x80E1048eDE66ec4c364b4F22C8768fc657FF6A42
            address upUSDCVault = 0x80E1048eDE66ec4c364b4F22C8768fc657FF6A42;
            // chainlink(USDC/USD): https://data.chain.link/feeds/ethereum/mainnet/usdc-usd-svr
            // heartBeat: 86400 (24hr)
            address usdcToUsd = 0xfB6471ACD42c91FF265344Ff73E88353521d099F;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usdcFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, upUSDCVault));
            (, int256 answer,,,) = usdcFeed.latestRoundData();
            console.log("upUSDC price feed description", usdcFeed.description());
            console.log("upUSDC price feed address", address(usdcFeed));
            console.log("upUSDC last answer", answer);
        }

        {
            // Usual(usualx): https://tech.usual.money/smart-contracts/contract-deployments
            address usualxVault = 0x06B964d96f5dCF7Eae9d7C559B09EDCe244d4B8E;
            // Redstone (USUAL/USD): https://app.redstone.finance/app/feeds/?search=USUAL&page=1&sortBy=popularity&sortDesc=false&perPage=32
            // heartBeat: 86400 (24hr)
            address usualToUsd = 0x2240AE461B34CC56D654ba5FA5830A243Ca54840;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface usualFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usualToUsd, usualxVault));
            (, int256 answer,,,) = usualFeed.latestRoundData();
            console.log("usualx price feed description", usualFeed.description());
            console.log("usualx price feed address", address(usualFeed));
            console.log("usualx last answer", answer);
        }

        vm.stopBroadcast();
    }
}
