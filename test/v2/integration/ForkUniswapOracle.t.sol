// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {ForkBaseTestV2, IERC20, IERC20Metadata} from "../mainnet-fork/ForkBaseTestV2.sol";
import {TermMaxUniswapTWAPPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxUniswapTWAPPriceFeed.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {console} from "forge-std/console.sol";

contract ForkUniswapOracle is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint32 _twapPeriod = 900;
    uint24 fee = 500;

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {}

    function testGetPrice() public {
        address pool = IUniswapV3Factory(uniswapFactory).getPool(WBTC, USDC, fee);
        TermMaxUniswapTWAPPriceFeed priceFeed = new TermMaxUniswapTWAPPriceFeed(pool, _twapPeriod, WBTC, USDC);
        (, int256 price,,,) = priceFeed.latestRoundData();
        console.log("price", price);
    }
}
