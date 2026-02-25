// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface, ITermMaxPriceFeed} from "../../priceFeeds/ITermMaxPriceFeed.sol";
import {IBeefyVaultV7} from "./IBeefyVaultV7.sol";
import {IKodiakIsland} from "./IKodiakIsland.sol";

/**
 * @title TermMaxBeefySharePriceFeedAdapter
 * @notice Quote Beefy share/USD price from LP composition and token price feeds
 * @dev token0/token1 price feeds must be bound to underlying token0/token1 respectively
 */
contract TermMaxBeefySharePriceFeedAdapter is ITermMaxPriceFeed {
    using Math for *;
    using SafeCast for *;

    error GetRoundDataNotSupported();
    error InvalidPrice(int256 answer);
    error InvalidWantAddress(address expected, address actual);

    uint256 internal constant OUTPUT_DECIMALS = 1e8;

    IBeefyVaultV7 public immutable beefyVault;
    IKodiakIsland public immutable lpToken;
    AggregatorV3Interface public immutable token0PriceFeed;
    AggregatorV3Interface public immutable token1PriceFeed;

    address public immutable asset;

    uint8 internal immutable token0PriceDecimals;
    uint8 internal immutable token1PriceDecimals;
    uint8 internal immutable token0Decimals;
    uint8 internal immutable token1Decimals;

    constructor(address _beefyVault, address _token0PriceFeed, address _token1PriceFeed) {
        beefyVault = IBeefyVaultV7(_beefyVault);
        token0PriceFeed = AggregatorV3Interface(_token0PriceFeed);
        token1PriceFeed = AggregatorV3Interface(_token1PriceFeed);

        asset = _beefyVault;

        address want = beefyVault.want();
        lpToken = IKodiakIsland(want);

        address token0 = lpToken.token0();
        address token1 = lpToken.token1();

        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
        token0PriceDecimals = token0PriceFeed.decimals();
        token1PriceDecimals = token1PriceFeed.decimals();
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        string memory symbol = IERC20Metadata(asset).symbol();
        return string(abi.encodePacked("TermMax price feed: ", symbol, "/USD"));
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 /* _roundId */ )
        external
        pure
        override
        returns (
            uint80, /* roundId */
            int256, /* answer */
            uint256, /* startedAt */
            uint256, /* updatedAt */
            uint80 /* answeredInRound */
        )
    {
        revert GetRoundDataNotSupported();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        address currentWant = beefyVault.want();
        if (currentWant != address(lpToken)) {
            revert InvalidWantAddress(address(lpToken), currentWant);
        }

        (, int256 answer0, uint256 startedAt0, uint256 updatedAt0,) = token0PriceFeed.latestRoundData();
        (, int256 answer1, uint256 startedAt1, uint256 updatedAt1,) = token1PriceFeed.latestRoundData();

        if (answer0 <= 0) revert InvalidPrice(answer0);
        if (answer1 <= 0) revert InvalidPrice(answer1);
        roundId = uint80(block.timestamp);
        answeredInRound = uint80(block.timestamp);
        startedAt = startedAt0.min(startedAt1);
        updatedAt = updatedAt0.min(updatedAt1);
        // Calculate a "fair" price for the LP using the underlying token prices, to prevent manipulation when vault is very imbalanced.
        uint160 fairSqrtPriceX96 = _computeFairSqrtPriceX96(answer0, answer1);
        answer = _computeFairValue(answer0, answer1, fairSqrtPriceX96).toInt256();
    }

    /// @dev Compute the fair share value using oracle-derived reserves.
    ///      Uses getUnderlyingBalancesAtPrice(fairSqrtPriceX96) instead of
    ///      getUnderlyingBalances() so the pool spot price cannot affect the result.
    ///
    ///      Precision note: the two-step split
    ///        token0PerShare = fairAmount0 * lpPerShare / (lpTotal * 1e18)   → may truncate to 0
    ///        value0         = token0PerShare * price / denom
    ///      is collapsed into a single mulDiv to avoid intermediate truncation:
    ///        value0 = fairAmount0 * (lpPerShare * price * OUTPUT_DECIMALS) / (lpTotal * 1e18 * denom)
    function _computeFairValue(int256 answer0, int256 answer1, uint160 fairSqrtPriceX96)
        internal
        view
        returns (uint256)
    {
        (uint256 fairAmount0, uint256 fairAmount1) = lpToken.getUnderlyingBalancesAtPrice(fairSqrtPriceX96);

        uint256 lpPerShare = beefyVault.getPricePerFullShare(); // LP per 1e18 mooToken
        uint256 lpTotal = lpToken.totalSupply();
        if (lpTotal == 0) {
            return 0;
        }

        uint256 tok0Denom = 10 ** (token0Decimals + token0PriceDecimals);
        uint256 tok1Denom = 10 ** (token1Decimals + token1PriceDecimals);

        // Single-step mulDiv avoids precision loss from intermediate truncation.
        // lpPerShare is already "LP for 1e18 vault shares", so the correct per-share
        // token amount is fairAmountN * lpPerShare / lpTotal (no extra 1e18 factor).
        uint256 value0 = fairAmount0.mulDiv(lpPerShare * answer0.toUint256() * OUTPUT_DECIMALS, lpTotal * tok0Denom);
        uint256 value1 = fairAmount1.mulDiv(lpPerShare * answer1.toUint256() * OUTPUT_DECIMALS, lpTotal * tok1Denom);
        return value0 + value1;
    }

    /// @dev Compute the oracle-derived fair sqrtPriceX96, i.e.
    ///      P_fair = (answer0 / 10^feed0Dec) / (answer1 / 10^feed1Dec)
    ///               * (10^token1Dec / 10^token0Dec)
    ///      sqrtPriceX96 = sqrt(P_fair) * 2^96
    function _computeFairSqrtPriceX96(int256 answer0, int256 answer1)
        internal
        view
        returns (uint160 fairSqrtPriceX96)
    {
        uint256 priceNum = uint256(answer0) * 10 ** (token1Decimals + token1PriceDecimals);
        uint256 priceDen = uint256(answer1) * 10 ** (token0Decimals + token0PriceDecimals);
        // mulDiv handles 512-bit intermediate product, avoiding overflow from (priceNum * 2^192)
        fairSqrtPriceX96 = uint160(Math.sqrt(priceNum.mulDiv(uint256(1) << 192, priceDen)));
    }
}
