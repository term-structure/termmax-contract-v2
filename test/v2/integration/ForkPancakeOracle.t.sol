// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {ForkBaseTestV2, IERC20, IERC20Metadata} from "../mainnet-fork/ForkBaseTestV2.sol";
import {TermMaxPancakeTWAPPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxPancakeTWAPPriceFeed.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {console} from "forge-std/console.sol";

contract ForkPancakeOracle is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address pancakeFactory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant BUSD = 0x55d398326f99059fF775485246999027B3197955;
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
        address pool = IUniswapV3Factory(pancakeFactory).getPool(WBNB, BUSD, fee);
        TermMaxPancakeTWAPPriceFeed priceFeed = new TermMaxPancakeTWAPPriceFeed(pool, _twapPeriod, WBNB, BUSD);
        (, int256 price,,,) = priceFeed.latestRoundData();
        console.log("price", price);
    }
}
