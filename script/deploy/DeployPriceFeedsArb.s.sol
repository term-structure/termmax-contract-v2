// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceFeedFactory} from "contracts/extensions/PriceFeedFactory.sol";

contract DeployPriceFeedsArb is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        PriceFeedFactory priceFeedFactory = new PriceFeedFactory();

        console.log("PriceFeedFactory deployed at", address(priceFeedFactory));

        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        address weEthOracle;
        {
            address wstEthToEth = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;
            address ethToUsd = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
            AggregatorV3Interface wstEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(wstEthToEth, ethToUsd));
            (, int256 answer,,,) = wstEthFeed.latestRoundData();
            console.log("wstEth price feed address", address(wstEthFeed));
            console.log("wstEth last answer", answer);
        }

        {
            address weEthToEth = 0xE141425bc1594b8039De6390db1cDaf4397EA22b;
            address ethToUsd = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
            AggregatorV3Interface weEthFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedConverter(weEthToEth, ethToUsd));
            (, int256 answer,,,) = weEthFeed.latestRoundData();
            console.log("weEth price feed address", address(weEthFeed));
            console.log("weEth last answer", answer);
            weEthOracle = address(weEthFeed);
        }

        {
            address PT_weETH_26JUN2025_market = 0xBf5E60ddf654085F80DAe9DD33Ec0E345773E1F8;

            AggregatorV3Interface ptFeed = AggregatorV3Interface(
                priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, PT_weETH_26JUN2025_market, 900, weEthOracle)
            );
            (, int256 answer,,,) = ptFeed.latestRoundData();
            console.log("pt_weETH_26JUN2025 price feed address", address(ptFeed));
            console.log("pt_weETH_26JUN2025 last answer", answer);
        }

        vm.stopBroadcast();
    }
}
