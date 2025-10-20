// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {VersionV2} from "../../VersionV2.sol";

contract TermMaxUniswapTWAPPriceFeed is ITermMaxPriceFeed, VersionV2 {
    address public immutable pool;
    uint32 public immutable twapPeriod;
    address public immutable baseToken;
    address public immutable quoteToken;
    uint128 private immutable baseAmount;
    uint8 private immutable quoteDecimals;

    error InvalidPool();
    error InsufficientObservationCardinality();
    error InsufficientObservationHistory();

    constructor(address _pool, uint32 _twapPeriod, address _baseToken, address _quoteToken) {
        pool = _pool;
        // check if the pool is valid
        (address token0, address token1) =
            _baseToken < _quoteToken ? (_baseToken, _quoteToken) : (_quoteToken, _baseToken);
        require(token0 == IUniswapV3Pool(_pool).token0(), InvalidPool());
        require(token1 == IUniswapV3Pool(_pool).token1(), InvalidPool());
        // check if the twapPeriod is valid
        require(_twapPeriod != 0, "TWAP period cannot be zero");
        _ensureSufficientObservations(_pool, _twapPeriod);

        twapPeriod = _twapPeriod;
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        baseAmount = uint128(10 ** IERC20Metadata(_baseToken).decimals());
        quoteDecimals = IERC20Metadata(_quoteToken).decimals();
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        return string(
            abi.encodePacked(
                "TermMax UniswapV3 TWAP price feed: ",
                IERC20Metadata(baseToken).symbol(),
                "/",
                IERC20Metadata(quoteToken).symbol()
            )
        );
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function latestRoundData()
        public
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (int24 arithmeticMeanTick,) = _consult(pool, twapPeriod);
        uint256 quoteAmount = _getQuoteAtTick(arithmeticMeanTick, baseAmount, baseToken, quoteToken);
        // Adjust the quoteAmount to have `decimals()` decimals
        uint256 standardizedPrice = (quoteAmount * 10 ** decimals()) / (10 ** quoteDecimals);
        answer = int256(standardizedPrice);
        roundId = uint80(block.number);
        startedAt = block.timestamp - twapPeriod;
        updatedAt = block.timestamp;
        answeredInRound = roundId;
    }

    function getRoundData(uint80 /* _roundId */ )
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return latestRoundData();
    }

    function asset() external view override returns (address) {
        return baseToken;
    }

    function _consult(address _pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        require(secondsAgo != 0, "Seconds ago cannot be zero");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            IUniswapV3Pool(_pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        uint160 secondsPerLiquidityCumulativesDelta =
            secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / int32(secondsAgo));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0)) arithmeticMeanTick--;

        // We are multiplying here instead of shifting to ensure that harmonicMeanLiquidity doesn't overflow uint128
        uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
        harmonicMeanLiquidity = uint128(secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32));
    }

    function _getQuoteAtTick(int24 tick, uint128 _baseAmount, address _baseToken, address _quoteToken)
        internal
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = _baseToken < _quoteToken
                ? FullMath.mulDiv(ratioX192, _baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, _baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = _baseToken < _quoteToken
                ? FullMath.mulDiv(ratioX128, _baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, _baseAmount, ratioX128);
        }
    }

    function _ensureSufficientObservations(address _pool, uint32 _twapPeriod) internal view virtual {
        (,, uint16 observationIndex, uint16 observationCardinality,,,) = IUniswapV3Pool(_pool).slot0();
        if (observationCardinality <= 1) revert InsufficientObservationCardinality();
        uint16 oldestIndex = uint16((uint256(observationIndex) + 1) % observationCardinality);
        (uint32 oldestTimestamp,,, bool oldestInitialized) = IUniswapV3Pool(_pool).observations(oldestIndex);
        uint256 currentTimestamp = block.timestamp;

        if (!oldestInitialized) {
            (uint32 latestTimestamp,,, bool latestInitialized) = IUniswapV3Pool(_pool).observations(observationIndex);
            if (!latestInitialized) revert InsufficientObservationHistory();
            if (currentTimestamp - uint256(latestTimestamp) < _twapPeriod) revert InsufficientObservationHistory();
            return;
        }

        if (oldestTimestamp == 0) revert InsufficientObservationHistory();
        if (currentTimestamp - uint256(oldestTimestamp) < _twapPeriod) revert InsufficientObservationHistory();
    }
}
