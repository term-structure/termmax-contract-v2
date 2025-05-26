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

        {
            // inceptionLRT(inwstETH): https://docs.inceptionlrt.com/contracts/addresses/lrts
            address inwstETHVault = 0xf9D9F828989A624423C48b95BC04E9Ae0ef5Ec97;
            // chainlink(wstETH/USD): https://data.chain.link/feeds/ethereum/mainnet/wsteth-usd
            // heartBeat: 86400  (24hr)
            address wstETHToUsd = 0x164b276057258d81941e97B0a900D4C7B358bCe0;
            // new price feed heartBeat = max(86400) = 86400 (24hr)
            AggregatorV3Interface inwstETHFeed =
                AggregatorV3Interface(priceFeedFactory.createPriceFeedWithERC4626(wstETHToUsd, inwstETHVault));
            (, int256 answer,,,) = inwstETHFeed.latestRoundData();
            console.log("inwstETH price feed address", address(inwstETHFeed));
            console.log("inwstETH last answer", answer);
        }

        vm.stopBroadcast();
    }
}
