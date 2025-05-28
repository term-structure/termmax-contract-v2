// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {SwapUnit, ITermMaxRouter, TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {
    IGearingToken,
    GearingTokenEvents,
    AbstractGearingToken,
    GtConfig
} from "contracts/tokens/AbstractGearingToken.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracle} from "contracts/oracle/IOracleV1.sol";
import {
    ForkBaseTest,
    TermMaxFactory,
    MarketConfig,
    IERC20,
    MarketInitialParams,
    IERC20Metadata
} from "test/mainnet-fork/ForkBaseTest.sol";
import {TermMaxPriceFeedFactory} from "contracts/factory/TermMaxPriceFeedFactory.sol";
import {console} from "forge-std/console.sol";

interface TestOracle is IOracle {
    function acceptPendingOracle(address asset) external;
    function oracles(address asset) external returns (address aggregator, address backupAggregator, uint32 heartbeat);
}

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
        TermMaxPriceFeedFactory priceFeedFactory = new TermMaxPriceFeedFactory();
        address pendlePYLpOracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        address ptMarket = 0x266728b30c98B24De810E3325aDC615486988Cb2;
        address mMEVToUsd = 0x5f09Aff8B9b1f488B7d1bbaD4D89648579e55d61;
        AggregatorV3Interface ptFeed =
            AggregatorV3Interface(priceFeedFactory.createPTWithPriceFeed(pendlePYLpOracle, ptMarket, 900, mMEVToUsd));
        (, int256 answer,,,) = ptFeed.latestRoundData();
        console.log("pt_mMEV_31JUL2025 price feed address", address(ptFeed));
        console.log("pt_mMEV_31JUL2025 last answer", answer);
    }
}
