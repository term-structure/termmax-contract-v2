// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {SimpleAggregator} from "contracts/v2/oracle/SimpleAggregator.sol";
import {IOracleV2, AggregatorV3Interface} from "contracts/v2/oracle/IOracleV2.sol";
import {TermMaxConstantPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxConstantPriceFeed.sol";

contract SimpleAggregatorTest is Test {
    SimpleAggregator public aggregator;
    TermMaxConstantPriceFeed public feed1;
    TermMaxConstantPriceFeed public feed2;

    address public constant ASSET1 = address(0x1);
    address public constant ASSET2 = address(0x2);

    int256 public constant PRICE1 = 2000e8; // $2000 with 8 decimals
    int256 public constant PRICE2 = 50000e8; // $50000 with 8 decimals

    function setUp() public {
        // Deploy constant price feeds
        feed1 = new TermMaxConstantPriceFeed(PRICE1);
        feed2 = new TermMaxConstantPriceFeed(PRICE2);

        // Deploy SimpleAggregator
        address[2] memory assets = [ASSET1, ASSET2];
        AggregatorV3Interface[2] memory oracles = [
            AggregatorV3Interface(address(feed1)),
            AggregatorV3Interface(address(feed2))
        ];

        aggregator = new SimpleAggregator(assets, oracles);
    }

    function test_Constructor() public view {
        // Verify oracles are set correctly
        assertEq(address(aggregator.oracles(ASSET1)), address(feed1), "Asset1 oracle not set correctly");
        assertEq(address(aggregator.oracles(ASSET2)), address(feed2), "Asset2 oracle not set correctly");
    }

    function test_GetPrice_Asset1() public view {
        (uint256 price, uint8 decimals) = aggregator.getPrice(ASSET1);

        assertEq(price, uint256(PRICE1), "Asset1 price incorrect");
        assertEq(decimals, 8, "Asset1 decimals incorrect");
    }

    function test_GetPrice_Asset2() public view {
        (uint256 price, uint8 decimals) = aggregator.getPrice(ASSET2);

        assertEq(price, uint256(PRICE2), "Asset2 price incorrect");
        assertEq(decimals, 8, "Asset2 decimals incorrect");
    }

    function test_GetPrice_MultipleCalls() public view {
        // Call getPrice multiple times to ensure consistency
        (uint256 price1a, uint8 decimals1a) = aggregator.getPrice(ASSET1);
        (uint256 price1b, uint8 decimals1b) = aggregator.getPrice(ASSET1);

        assertEq(price1a, price1b, "Asset1 price should be consistent");
        assertEq(decimals1a, decimals1b, "Asset1 decimals should be consistent");

        (uint256 price2a, uint8 decimals2a) = aggregator.getPrice(ASSET2);
        (uint256 price2b, uint8 decimals2b) = aggregator.getPrice(ASSET2);

        assertEq(price2a, price2b, "Asset2 price should be consistent");
        assertEq(decimals2a, decimals2b, "Asset2 decimals should be consistent");
    }

    function test_GetPrice_UnregisteredAsset() public {
        address unregisteredAsset = address(0x999);

        // This should revert because the oracle is not set (address(0))
        vm.expectRevert();
        aggregator.getPrice(unregisteredAsset);
    }

    function test_SubmitPendingOracle_DoesNothing() public {
        // submitPendingOracle is a no-op in SimpleAggregator
        IOracleV2.Oracle memory oracle = IOracleV2.Oracle({
            aggregator: AggregatorV3Interface(address(0)),
            backupAggregator: AggregatorV3Interface(address(0)),
            heartbeat: 0,
            backupHeartbeat: 0,
            maxPrice: 0,
            minPrice: 0
        });

        // Should not revert, but does nothing
        aggregator.submitPendingOracle(ASSET1, oracle);
    }

    function test_AcceptPendingOracle_DoesNothing() public {
        // acceptPendingOracle is a no-op in SimpleAggregator
        aggregator.acceptPendingOracle(ASSET1);
    }

    function test_RevokePendingOracle_DoesNothing() public {
        // revokePendingOracle is a no-op in SimpleAggregator
        aggregator.revokePendingOracle(ASSET1);
    }

    function test_Fuzz_GetPrice(int256 price) public {
        // Bound the price to reasonable positive values
        vm.assume(price > 0);
        vm.assume(price <= type(int256).max);

        // Deploy new constant feed with fuzzed price
        TermMaxConstantPriceFeed fuzzFeed = new TermMaxConstantPriceFeed(price);

        // Deploy new aggregator with fuzzed feed
        address fuzzAsset = address(0x3);
        address[2] memory assets = [fuzzAsset, ASSET2];
        AggregatorV3Interface[2] memory oracles = [
            AggregatorV3Interface(address(fuzzFeed)),
            AggregatorV3Interface(address(feed2))
        ];

        SimpleAggregator fuzzAggregator = new SimpleAggregator(assets, oracles);

        // Test that the price is returned correctly
        (uint256 returnedPrice, uint8 decimals) = fuzzAggregator.getPrice(fuzzAsset);

        assertEq(returnedPrice, uint256(price), "Fuzzed price incorrect");
        assertEq(decimals, 8, "Decimals should always be 8");
    }

    function test_GetPrice_WithZeroPrice() public {
        // Test with zero price (edge case)
        TermMaxConstantPriceFeed zeroFeed = new TermMaxConstantPriceFeed(0);

        address zeroAsset = address(0x4);
        address[2] memory assets = [zeroAsset, ASSET2];
        AggregatorV3Interface[2] memory oracles = [
            AggregatorV3Interface(address(zeroFeed)),
            AggregatorV3Interface(address(feed2))
        ];

        SimpleAggregator zeroAggregator = new SimpleAggregator(assets, oracles);

        (uint256 price, uint8 decimals) = zeroAggregator.getPrice(zeroAsset);

        assertEq(price, 0, "Zero price should be returned");
        assertEq(decimals, 8, "Decimals should be 8");
    }

    function test_GetPrice_WithMaxPrice() public {
        // Test with maximum int256 price
        int256 maxPrice = type(int256).max;
        TermMaxConstantPriceFeed maxFeed = new TermMaxConstantPriceFeed(maxPrice);

        address maxAsset = address(0x5);
        address[2] memory assets = [maxAsset, ASSET2];
        AggregatorV3Interface[2] memory oracles = [
            AggregatorV3Interface(address(maxFeed)),
            AggregatorV3Interface(address(feed2))
        ];

        SimpleAggregator maxAggregator = new SimpleAggregator(assets, oracles);

        (uint256 price, uint8 decimals) = maxAggregator.getPrice(maxAsset);

        assertEq(price, uint256(maxPrice), "Max price should be returned");
        assertEq(decimals, 8, "Decimals should be 8");
    }

    function test_Constructor_WithSameAsset() public {
        // Test that both oracles can be set even if for same asset (constructor allows it)
        address[2] memory assets = [ASSET1, ASSET1];
        AggregatorV3Interface[2] memory oracles = [
            AggregatorV3Interface(address(feed1)),
            AggregatorV3Interface(address(feed2))
        ];

        SimpleAggregator duplicateAggregator = new SimpleAggregator(assets, oracles);

        // The second one should overwrite the first
        (uint256 price, uint8 decimals) = duplicateAggregator.getPrice(ASSET1);

        // Should return feed2's price since it was set last
        assertEq(price, uint256(PRICE2), "Should return second feed's price");
        assertEq(decimals, 8, "Decimals should be 8");
    }

    function test_OracleMapping() public view {
        // Test direct access to oracles mapping
        AggregatorV3Interface oracle1 = aggregator.oracles(ASSET1);
        AggregatorV3Interface oracle2 = aggregator.oracles(ASSET2);

        assertEq(address(oracle1), address(feed1), "Oracle1 mapping incorrect");
        assertEq(address(oracle2), address(feed2), "Oracle2 mapping incorrect");

        // Test unregistered asset returns zero address
        AggregatorV3Interface unregisteredOracle = aggregator.oracles(address(0x999));
        assertEq(address(unregisteredOracle), address(0), "Unregistered oracle should be zero address");
    }

    function test_GetPrice_VerifyLatestRoundData() public view {
        // Verify that getPrice calls latestRoundData correctly
        AggregatorV3Interface oracle = aggregator.oracles(ASSET1);
        (, int256 expectedAnswer,,,) = oracle.latestRoundData();

        (uint256 price,) = aggregator.getPrice(ASSET1);

        assertEq(price, uint256(expectedAnswer), "Price should match oracle's latestRoundData");
    }
}
