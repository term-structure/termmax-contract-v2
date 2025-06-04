// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../ForkBaseTest.sol";
import {PriceFeedFactory} from "contracts/v1/extensions/PriceFeedFactory.sol";

contract ForkPriceFeed is ForkBaseTest {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testPriceFeed() public {
        PriceFeedFactory priceFeedFactory = new PriceFeedFactory();
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        address pufferEthOracle;
        {
            address pufferEthToEth = 0x76A495b0bFfb53ef3F0E94ef0763e03cE410835C;
            address ethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            AggregatorV3Interface pufferEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(pufferEthToEth, ethToUsd));
            (, int256 answer,,,) = pufferEthFeed.latestRoundData();
            console.log("pufferEth price feed address", address(pufferEthFeed));
            console.log("pufferEth last answer", answer);
            pufferEthOracle = address(pufferEthFeed);
        }

        {
            address pt_market = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
            address susdeToUsd = 0xFF3BC18cCBd5999CE63E788A1c250a88626aD099;

            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, pt_market, 900, susdeToUsd)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_sUsde_29MAY2025 price feed address", address(ptFeed));
            console.log("pt_sUsde_29MAY2025 last answer", answer);
        }

        {
            address USUALUSDCPlusVault = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            AggregatorV3Interface usdcPlusFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, USUALUSDCPlusVault));
            (, int256 answer,,,) = usdcPlusFeed.latestRoundData();
            console.log("USUALUSDC+ price feed address", address(usdcPlusFeed));
            console.log("USUALUSDC+ last answer", answer);
        }

        {
            address MCwETHVault = 0x9a8bC3B04b7f3D87cfC09ba407dCED575f2d61D8;
            address wethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
            AggregatorV3Interface wethFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wethToUsd, MCwETHVault));
            (, int256 answer,,,) = wethFeed.latestRoundData();
            console.log("MCwETH price feed address", address(wethFeed));
            console.log("MCwETH last answer", answer);
        }

        {
            address PT_pufETH_26JUN2025_market = 0x58612beB0e8a126735b19BB222cbC7fC2C162D2a;
            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(
                    pendlePYLpOracle, PT_pufETH_26JUN2025_market, 900, pufferEthOracle
                )
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_pufETH_26JUN2025 price feed address", address(ptFeed));
            console.log("pt_pufETH_26JUN2025 last answer", answer);
        }

        {
            address eUSDeVault = 0x90D2af7d622ca3141efA4d8f1F24d86E5974Cc8F;
            address usdeToUsd = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;
            AggregatorV3Interface usdeFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdeToUsd, eUSDeVault));
            (, int256 answer,,,) = usdeFeed.latestRoundData();
            console.log("eUSDe price feed address", address(usdeFeed));
            console.log("eUSDe last answer", answer);
        }

        {
            address PT_USD0PlusPlus_26JUN2025_market = 0x048680F64d6DFf1748ba6D9a01F578433787e24B;
            address usd0PlusPlusToUsd = 0xFC9e30Cf89f8A00dba3D34edf8b65BCDAdeCC1cB;
            AggregatorV3Interface usd0PlusPlusFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(
                    pendlePYLpOracle, PT_USD0PlusPlus_26JUN2025_market, 900, usd0PlusPlusToUsd
                )
            );
            (, int256 answer,,,) = usd0PlusPlusFeed.latestRoundData();
            console.log("PT_USD0PlusPlus_26JUN2025_market price feed address", address(usd0PlusPlusFeed));
            console.log("PT_USD0PlusPlus_26JUN2025_market last answer", answer);
        }

        {
            address upUSDCVault = 0x80E1048eDE66ec4c364b4F22C8768fc657FF6A42;
            address usdcToUsd = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
            AggregatorV3Interface usdcFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usdcToUsd, upUSDCVault));
            (, int256 answer,,,) = usdcFeed.latestRoundData();
            console.log("upUSDC price feed address", address(usdcFeed));
            console.log("upUSDC last answer", answer);
        }

        {
            address usualxVault = 0x06B964d96f5dCF7Eae9d7C559B09EDCe244d4B8E;
            address usualToUsd = 0x2240AE461B34CC56D654ba5FA5830A243Ca54840;
            AggregatorV3Interface usualFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(usualToUsd, usualxVault));
            (, int256 answer,,,) = usualFeed.latestRoundData();
            console.log("usualx price feed address", address(usualFeed));
            console.log("usualx last answer", answer);
        }
    }
}
