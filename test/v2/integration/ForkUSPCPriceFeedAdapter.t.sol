// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TermMaxUSPCPriceFeedAdapter} from "contracts/v2/oracle/priceFeeds/TermMaxUSPCPriceFeedAdapter.sol";

interface IUSPCOracle {
    function getLatestPriceInfo() external view returns (uint256 price, uint256 timestamp);
}

/**
 * @title ForkUSPCPriceFeedAdapterTest
 * @notice Fork integration test for TermMaxUSPCPriceFeedAdapter
 */
contract ForkUSPCPriceFeedAdapterTest is Test {
    TermMaxUSPCPriceFeedAdapter public adapter;
    IUSPCOracle public uspcOracle;

    // b2-mainnet addresses provided by user
    address internal constant USPC_ORACLE = 0x5eC0C20A83554eC1BBC0F1D3414BB8746a04acD4;
    address internal constant USPC_ASSET = 0xdc807c3a618B6B1248481783def7ED76700B9eC6;

    uint8 internal constant ADAPTER_DECIMALS = 18;
    uint256 internal constant SCALE_DOWN = 1e18;

    string internal MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 forkId = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(forkId);

        adapter = new TermMaxUSPCPriceFeedAdapter(USPC_ORACLE, USPC_ASSET);
        uspcOracle = IUSPCOracle(USPC_ORACLE);
    }

    function testAdapterInitialization() public view {
        assertEq(address(adapter.uspcOracle()), USPC_ORACLE, "USPC oracle address should match");
        assertEq(adapter.asset(), USPC_ASSET, "asset address should match");
    }

    function testDecimals() public view {
        assertEq(adapter.decimals(), ADAPTER_DECIMALS, "adapter decimals should be 18");
    }

    function testDescription() public view {
        string memory desc = adapter.description();
        assertTrue(bytes(desc).length > 0, "description should not be empty");
    }

    function testVersion() public view {
        assertEq(adapter.version(), 1, "version should be 1");
    }

    function testLatestRoundData() public view {
        (uint256 oraclePrice36, uint256 oracleTimestamp) = uspcOracle.getLatestPriceInfo();
        uint256 expectedPrice18 = oraclePrice36 / SCALE_DOWN;

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            adapter.latestRoundData();

        assertEq(roundId, 1, "roundId should be 1");
        assertEq(answeredInRound, 1, "answeredInRound should be 1");
        assertEq(startedAt, oracleTimestamp, "startedAt should equal oracle timestamp");
        assertEq(updatedAt, oracleTimestamp, "updatedAt should equal oracle timestamp");
        assertEq(uint256(answer), expectedPrice18, "answer should equal oracle price scaled from 36 to 18");
    }

    function testLatestRoundDataPriceIsPositive() public view {
        (, int256 answer,,,) = adapter.latestRoundData();
        assertGt(answer, 0, "answer should be positive");
    }

    function testGetRoundDataReverts() public {
        vm.expectRevert(TermMaxUSPCPriceFeedAdapter.GetRoundDataNotSupported.selector);
        adapter.getRoundData(1);
    }
}
