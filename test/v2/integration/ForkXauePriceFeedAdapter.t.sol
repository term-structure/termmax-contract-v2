// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {
    TermMaxXauePricefeedAdapter,
    IXaueOracle,
    AggregatorV3Interface
} from "contracts/v2/oracle/adapters/xaue/TermMaxXauePricefeedAdapter.sol";
import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TermMaxPriceFeedFactoryV2} from "contracts/v2/factory/TermMaxPricefeedFactoryV2.sol";

/**
 * @title ForkXauePriceFeedAdapterTest
 * @notice Fork integration test for TermMaxXauePriceFeedAdapter using XAUE/XAUT pair
 */
contract ForkXauePriceFeedAdapterTest is Test {
    using SafeCast for uint256;

    TermMaxXauePricefeedAdapter public adapter;
    IXaueOracle public xaueOracle;

    // keep using existing env key in repo's fork tests
    string internal MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 forkId = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(forkId);

        adapter = new TermMaxXauePricefeedAdapter();
        xaueOracle = adapter.xaueOracle();
    }

    function testLatestPrice() public view {
        (, int256 answer, uint256 timestamp,,) = adapter.latestRoundData();
        console.log("Adapter price:", answer);
        console.log("Adapter timestamp:", timestamp);
        uint256 oraclePrice = xaueOracle.getLatestPrice();
        assertEq(uint256(answer), oraclePrice, "Adapter price should match oracle price");
        assertEq(timestamp, xaueOracle.lastUpdateTimestamp(), "Adapter timestamp should match oracle timestamp");
    }

    function testInegration() public {
        TermMaxPriceFeedFactoryV2 factory = TermMaxPriceFeedFactoryV2(0xFD9B5ee419C56f5ED3E86ba70953342906a7dE2B);
        address xaue = 0xd5D6840ed95F58FAf537865DcA15D5f99195F87a;
        address xautOracle = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;
        AggregatorV3Interface priceFeed =
            AggregatorV3Interface(factory.createPriceFeedConverter(address(adapter), xautOracle, xaue));
        (, int256 answer, uint256 timestamp,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        console.log("Price feed decimals:", decimals);
        console.log("Description:", priceFeed.description());
        console.log("Adapter price feed price:", answer);
        console.log("Adapter price feed timestamp:", timestamp);
        console.log("Price with decimals 8:", uint256(answer) * 10 ** (8 - decimals));
    }
}
