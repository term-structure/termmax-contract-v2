// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {TermMaxUniswapTWAPPriceFeed} from "contracts/v2/oracle/priceFeeds/TermMaxUniswapTWAPPriceFeed.sol";

contract MockUniswapV3Pool {
    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }

    struct ObservationSnapshot {
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool set;
    }

    address private _token0;
    address private _token1;
    uint160 private _sqrtPriceX96;
    int24 private _tick;
    uint16 private _observationIndex;
    uint16 private _observationCardinality;
    uint16 private _observationCardinalityNext;
    uint8 private _feeProtocol;
    bool private _unlocked = true;

    mapping(uint256 => Observation) private _observations;
    mapping(uint32 => ObservationSnapshot) private _snapshots;

    constructor(address token0_, address token1_) {
        _token0 = token0_;
        _token1 = token1_;
    }

    function setTokenOrdering(address token0_, address token1_) external {
        _token0 = token0_;
        _token1 = token1_;
    }

    function setSlot0(
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext
    ) external {
        _sqrtPriceX96 = sqrtPriceX96;
        _tick = tick;
        _observationIndex = observationIndex;
        _observationCardinality = observationCardinality;
        _observationCardinalityNext = observationCardinalityNext;
    }

    function setObservation(
        uint16 index,
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    ) external {
        _observations[index] =
            Observation(blockTimestamp, tickCumulative, secondsPerLiquidityCumulativeX128, initialized);
    }

    function setSnapshot(uint32 secondsAgo, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) external {
        _snapshots[secondsAgo] = ObservationSnapshot(tickCumulative, secondsPerLiquidityCumulativeX128, true);
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (
            _sqrtPriceX96,
            _tick,
            _observationIndex,
            _observationCardinality,
            _observationCardinalityNext,
            _feeProtocol,
            _unlocked
        );
    }

    function observations(uint256 index) external view returns (uint32, int56, uint160, bool) {
        Observation memory obs = _observations[index];
        return (obs.blockTimestamp, obs.tickCumulative, obs.secondsPerLiquidityCumulativeX128, obs.initialized);
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        uint256 length = secondsAgos.length;
        tickCumulatives = new int56[](length);
        secondsPerLiquidityCumulativeX128s = new uint160[](length);

        for (uint256 i = 0; i < length; i++) {
            ObservationSnapshot memory snapshot = _snapshots[secondsAgos[i]];
            require(snapshot.set, "snapshot missing");
            tickCumulatives[i] = snapshot.tickCumulative;
            secondsPerLiquidityCumulativeX128s[i] = snapshot.secondsPerLiquidityCumulativeX128;
        }
    }
}

contract TermMaxUniswapTWAPPriceFeedTest is Test {
    uint32 constant TWAP_PERIOD = 600;

    MockERC20 internal baseToken;
    MockERC20 internal quoteToken;
    MockUniswapV3Pool internal mockPool;

    function setUp() public {
        baseToken = new MockERC20("Base Token", "BASE", 18);
        quoteToken = new MockERC20("Quote Token", "QUOTE", 6);

        address token0Address = address(baseToken) < address(quoteToken) ? address(baseToken) : address(quoteToken);
        address token1Address = address(baseToken) < address(quoteToken) ? address(quoteToken) : address(baseToken);

        mockPool = new MockUniswapV3Pool(token0Address, token1Address);
    }

    function _configureReadyPool(uint32 currentTimestamp) internal {
        vm.warp(currentTimestamp);

        mockPool.setSlot0(0, 0, 1, 4, 4);

        // Oldest observation (index 2) is initialized and sufficiently old
        mockPool.setObservation(2, currentTimestamp - 3600, 1_000, 500, true);
        // Latest observation (index 1)
        mockPool.setObservation(1, currentTimestamp, 2_200, 1_100, true);

        // Snapshots for observe(secondsAgo)
        mockPool.setSnapshot(TWAP_PERIOD, 1_000, 500);
        mockPool.setSnapshot(0, 2_200, 1_100);
    }

    function _deployFeed() internal returns (TermMaxUniswapTWAPPriceFeed) {
        return new TermMaxUniswapTWAPPriceFeed(address(mockPool), TWAP_PERIOD, address(baseToken), address(quoteToken));
    }

    function testLatestRoundDataComputesExpectedPrice() public {
        uint32 currentTimestamp = 1_000_000;
        _configureReadyPool(currentTimestamp);

        TermMaxUniswapTWAPPriceFeed feed = _deployFeed();

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answeredInRound, 1);
        assertEq(startedAt, currentTimestamp - TWAP_PERIOD);
        assertEq(updatedAt, currentTimestamp);

        int24 expectedTick = 2; // (2_200 - 1_000) / 600
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(expectedTick);
        uint128 baseAmount = uint128(10 ** baseToken.decimals());
        bool baseIsToken0 = address(baseToken) < address(quoteToken);
        uint256 quoteAmount;

        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            if (baseIsToken0) {
                quoteAmount = FullMath.mulDiv(ratioX192, baseAmount, 1 << 192);
            } else {
                quoteAmount = FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
            }
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            if (baseIsToken0) {
                quoteAmount = FullMath.mulDiv(ratioX128, baseAmount, 1 << 128);
            } else {
                quoteAmount = FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
            }
        }

        uint256 expectedStandardized = (quoteAmount * 10 ** feed.decimals()) / (10 ** quoteToken.decimals());
        assertEq(answer, int256(expectedStandardized));
        assertEq(feed.asset(), address(baseToken));
    }

    function testDecimals() public {
        _configureReadyPool(1_500_000);
        TermMaxUniswapTWAPPriceFeed feed = _deployFeed();

        assertEq(feed.decimals(), 8);
    }

    function testDescription() public {
        _configureReadyPool(1_600_000);
        TermMaxUniswapTWAPPriceFeed feed = _deployFeed();

        assertEq(feed.description(), "TermMax UniswapV3 TWAP price feed: BASE/QUOTE");
    }

    function testVersion() public {
        _configureReadyPool(1_700_000);
        TermMaxUniswapTWAPPriceFeed feed = _deployFeed();

        assertEq(feed.version(), 1);
    }

    function testConstructorRevertsWhenObservationCardinalityTooLow() public {
        vm.warp(1); // ensure block.timestamp > 0
        mockPool.setSlot0(0, 0, 0, 1, 1);

        vm.expectRevert(TermMaxUniswapTWAPPriceFeed.InsufficientObservationCardinality.selector);
        _deployFeed();
    }

    function testConstructorRevertsWhenLatestObservationTooRecent() public {
        uint32 currentTimestamp = 1000;
        vm.warp(currentTimestamp);

        mockPool.setSlot0(0, 0, 0, 2, 2);
        mockPool.setObservation(0, currentTimestamp - 100, 0, 0, true);
        // observation index 1 is not initialized, triggering fallback path that checks latest observation recency

        vm.expectRevert(TermMaxUniswapTWAPPriceFeed.InsufficientObservationHistory.selector);
        _deployFeed();
    }

    function testConstructorRevertsWhenOldestObservationTooRecent() public {
        uint32 currentTimestamp = 2000;
        vm.warp(currentTimestamp);

        mockPool.setSlot0(0, 0, 1, 3, 3);
        mockPool.setObservation(1, currentTimestamp, 0, 0, true);
        mockPool.setObservation(2, currentTimestamp - (TWAP_PERIOD / 2), 0, 0, true);

        vm.expectRevert(TermMaxUniswapTWAPPriceFeed.InsufficientObservationHistory.selector);
        _deployFeed();
    }
}
