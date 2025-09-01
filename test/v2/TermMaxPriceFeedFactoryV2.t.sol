// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {TermMaxPriceFeedFactoryV2} from "contracts/v2/factory/TermMaxPriceFeedFactoryV2.sol";
import {TermMaxERC4626PriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxERC4626PriceFeed.sol";
import {TermMaxPriceFeedConverter} from "contracts/v2/oracle/priceFeeds/TermMaxPriceFeedConverter.sol";
import {TermMaxPTPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxPTPriceFeed.sol";
import {TermMaxConstantPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxConstantPriceFeed.sol";
import {FactoryEventsV2} from "contracts/v2/events/FactoryEventsV2.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";

// Mock ERC4626 vault for testing
contract MockERC4626 {
    string public name = "Mock Vault";
    string public symbol = "MVAULT";
    uint8 public decimals = 18;
    address public asset;

    constructor(address _asset) {
        asset = _asset;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares * 11 / 10; // 1.1x exchange rate
    }
}

// Mock Pendle oracle for testing
contract MockPendlePYLpOracle {
    function getOracleState(address, uint32)
        external
        pure
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied)
    {
        return (false, 0, true);
    }

    function getPtToAssetRate(address, uint32) external pure returns (uint256) {
        return 1e18; // 1:1 rate
    }
}

// Mock SY and PT tokens used by Pendle market
contract MockSY {
    uint8 private _decimals;
    string public symbol = "sSY";

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

contract MockPT {
    uint8 private _decimals;
    string public symbol = "pPT";

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

// Mock Pendle market for testing
contract MockPendleMarket {
    MockSY public sy;
    MockPT public pt;

    constructor() {
        sy = new MockSY(18);
        pt = new MockPT(18);
    }

    // readTokens returns (IStandardizedYield, IPPrincipalToken, address). We return our mocks' addresses.
    function readTokens() external view returns (address, address, address) {
        return (address(sy), address(pt), address(0));
    }

    // Simulate getPtToSyRate used in PT price feed
    function getPtToSyRate(uint32) external pure returns (uint256) {
        return 1e18; // 1:1
    }
}

contract TermMaxPriceFeedFactoryV2Test is Test {
    TermMaxPriceFeedFactoryV2 public factory;
    MockERC20 public mockToken;
    MockERC4626 public mockVault;
    MockPriceFeed public mockPriceFeed1;
    MockPriceFeed public mockPriceFeed2;
    MockPendlePYLpOracle public mockPendleOracle;
    MockPendleMarket public mockPendleMarket;

    address public deployer = vm.randomAddress();

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy factory
        factory = new TermMaxPriceFeedFactoryV2();

        // Deploy mock contracts
        mockToken = new MockERC20("Test Token", "TEST", 18);
        mockVault = new MockERC4626(address(mockToken));
        mockPriceFeed1 = new MockPriceFeed(deployer);
        mockPriceFeed2 = new MockPriceFeed(deployer);
        mockPendleOracle = new MockPendlePYLpOracle();
        mockPendleMarket = new MockPendleMarket();

        // Set up mock price feeds with initial data
        mockPriceFeed1.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: 2000e8, // $2000
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );

        mockPriceFeed2.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: 1e8, // 1:1 conversion rate
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );

        vm.stopPrank();
    }

    function testCreatePriceFeedWithERC4626() public {
        vm.startPrank(deployer);

        // Test successful creation
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0)); // only check event signature

        address priceFeedAddress = factory.createPriceFeedWithERC4626(address(mockPriceFeed1), address(mockVault));

        // Verify the price feed was created correctly
        assertNotEq(priceFeedAddress, address(0));

        TermMaxERC4626PriceFeed priceFeed = TermMaxERC4626PriceFeed(priceFeedAddress);
        // In TermMaxERC4626PriceFeed, the vault address is stored in the 'asset' field
        assertEq(priceFeed.asset(), address(mockVault));
        assertEq(address(priceFeed.assetPriceFeed()), address(mockPriceFeed1));

        vm.stopPrank();
    }

    function testCreatePriceFeedWithERC4626WithZeroAddresses() public {
        vm.startPrank(deployer);

        // Expect revert when passing zero addresses because constructors call external methods
        vm.expectRevert();
        factory.createPriceFeedWithERC4626(address(0), address(mockVault));

        vm.expectRevert();
        factory.createPriceFeedWithERC4626(address(mockPriceFeed1), address(0));

        vm.stopPrank();
    }

    function testCreatePriceFeedConverter() public {
        vm.startPrank(deployer);

        // Test successful creation
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0));

        address priceFeedAddress =
            factory.createPriceFeedConverter(address(mockPriceFeed1), address(mockPriceFeed2), address(mockToken));

        // Verify the price feed was created correctly
        assertNotEq(priceFeedAddress, address(0));

        TermMaxPriceFeedConverter priceFeed = TermMaxPriceFeedConverter(priceFeedAddress);
        assertEq(priceFeed.asset(), address(mockToken));
        assertEq(address(priceFeed.aTokenToBTokenPriceFeed()), address(mockPriceFeed1));
        assertEq(address(priceFeed.bTokenToCTokenPriceFeed()), address(mockPriceFeed2));

        vm.stopPrank();
    }

    function testCreatePriceFeedConverterWithZeroAddresses() public {
        vm.startPrank(deployer);

        // Constructor will revert when provided zero address because it calls decimals() on feeds
        vm.expectRevert();
        factory.createPriceFeedConverter(address(0), address(0), address(0));

        vm.stopPrank();
    }

    function testCreatePTWithPriceFeed() public {
        vm.startPrank(deployer);

        uint32 duration = 3600; // 1 hour

        // Test successful creation
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0)); // only check event signature

        address priceFeedAddress = factory.createPTWithPriceFeed(
            address(mockPendleOracle), address(mockPendleMarket), duration, address(mockPriceFeed1)
        );

        // Verify the price feed was created correctly
        assertNotEq(priceFeedAddress, address(0));

        TermMaxPTPriceFeed priceFeed = TermMaxPTPriceFeed(priceFeedAddress);
        assertEq(address(priceFeed.PY_LP_ORACLE()), address(mockPendleOracle));
        assertEq(address(priceFeed.MARKET()), address(mockPendleMarket));
        assertEq(priceFeed.DURATION(), duration);
        assertEq(address(priceFeed.PRICE_FEED()), address(mockPriceFeed1));

        vm.stopPrank();
    }

    function testCreatePTWithPriceFeedWithDifferentDurations() public {
        vm.startPrank(deployer);

        // Test with different duration values
        uint32[] memory durations = new uint32[](3);
        durations[0] = 900; // 15 minutes
        durations[1] = 3600; // 1 hour
        durations[2] = 86400; // 1 day

        for (uint256 i = 0; i < durations.length; i++) {
            address priceFeedAddress = factory.createPTWithPriceFeed(
                address(mockPendleOracle), address(mockPendleMarket), durations[i], address(mockPriceFeed1)
            );

            assertNotEq(priceFeedAddress, address(0));
            TermMaxPTPriceFeed priceFeed = TermMaxPTPriceFeed(priceFeedAddress);
            assertEq(priceFeed.DURATION(), durations[i]);
        }

        vm.stopPrank();
    }

    function testCreateConstantPriceFeed() public {
        vm.startPrank(deployer);

        int256 constantPrice = 1e8; // $1.00

        // Test successful creation
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0)); // only check event signature

        address priceFeedAddress = factory.createConstantPriceFeed(constantPrice);

        // Verify the price feed was created correctly
        assertNotEq(priceFeedAddress, address(0));

        TermMaxConstantPriceFeed priceFeed = TermMaxConstantPriceFeed(priceFeedAddress);
        (, int256 answer,,,) = priceFeed.latestRoundData();
        assertEq(answer, constantPrice);

        vm.stopPrank();
    }

    function testCreateConstantPriceFeedWithDifferentPrices() public {
        vm.startPrank(deployer);

        // Test with different price values
        int256[] memory prices = new int256[](5);
        prices[0] = 0; // Zero price
        prices[1] = 1e8; // $1.00
        prices[2] = 2000e8; // $2000.00
        prices[3] = -1e8; // Negative price (for testing edge cases)
        prices[4] = type(int256).max; // Maximum value

        for (uint256 i = 0; i < prices.length; i++) {
            address priceFeedAddress = factory.createConstantPriceFeed(prices[i]);

            assertNotEq(priceFeedAddress, address(0));
            TermMaxConstantPriceFeed priceFeed = TermMaxConstantPriceFeed(priceFeedAddress);
            (, int256 answer,,,) = priceFeed.latestRoundData();
            assertEq(answer, prices[i]);
        }

        vm.stopPrank();
    }

    function testFactoryVersionV2() public view {
        // Test that the factory implements VersionV2
        assertEq(factory.getVersion(), "2.0.0");
    }

    function testMultiplePriceFeedCreations() public {
        vm.startPrank(deployer);

        // Create multiple price feeds of different types
        address erc4626Feed = factory.createPriceFeedWithERC4626(address(mockPriceFeed1), address(mockVault));

        address converterFeed =
            factory.createPriceFeedConverter(address(mockPriceFeed1), address(mockPriceFeed2), address(mockToken));

        address ptFeed = factory.createPTWithPriceFeed(
            address(mockPendleOracle), address(mockPendleMarket), 3600, address(mockPriceFeed1)
        );

        address constantFeed = factory.createConstantPriceFeed(1e8);

        // Verify all addresses are different and non-zero
        assertNotEq(erc4626Feed, address(0));
        assertNotEq(converterFeed, address(0));
        assertNotEq(ptFeed, address(0));
        assertNotEq(constantFeed, address(0));

        assertNotEq(erc4626Feed, converterFeed);
        assertNotEq(erc4626Feed, ptFeed);
        assertNotEq(erc4626Feed, constantFeed);
        assertNotEq(converterFeed, ptFeed);
        assertNotEq(converterFeed, constantFeed);
        assertNotEq(ptFeed, constantFeed);

        vm.stopPrank();
    }

    function testEventEmissionForAllMethods() public {
        vm.startPrank(deployer);

        // Test ERC4626 price feed event (only check signature)
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0));
        factory.createPriceFeedWithERC4626(address(mockPriceFeed1), address(mockVault));

        // Test converter price feed event
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0));
        factory.createPriceFeedConverter(address(mockPriceFeed1), address(mockPriceFeed2), address(mockToken));

        // Test PT price feed event
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0));
        factory.createPTWithPriceFeed(
            address(mockPendleOracle), address(mockPendleMarket), 3600, address(mockPriceFeed1)
        );

        // Test constant price feed event
        vm.expectEmit(false, false, false, false);
        emit FactoryEventsV2.PriceFeedCreated(address(0));
        factory.createConstantPriceFeed(1e8);

        vm.stopPrank();
    }

    function testFuzzCreateConstantPriceFeed(int256 price) public {
        vm.startPrank(deployer);

        address priceFeedAddress = factory.createConstantPriceFeed(price);
        assertNotEq(priceFeedAddress, address(0));

        TermMaxConstantPriceFeed priceFeed = TermMaxConstantPriceFeed(priceFeedAddress);
        (, int256 answer,,,) = priceFeed.latestRoundData();
        assertEq(answer, price);

        vm.stopPrank();
    }

    function testFuzzCreatePTWithPriceFeedDuration(uint32 duration) public {
        vm.assume(duration > 0 && duration < 365 days); // Reasonable duration bounds
        vm.startPrank(deployer);

        address priceFeedAddress = factory.createPTWithPriceFeed(
            address(mockPendleOracle), address(mockPendleMarket), duration, address(mockPriceFeed1)
        );

        assertNotEq(priceFeedAddress, address(0));
        TermMaxPTPriceFeed priceFeed = TermMaxPTPriceFeed(priceFeedAddress);
        assertEq(priceFeed.DURATION(), duration);

        vm.stopPrank();
    }
}
