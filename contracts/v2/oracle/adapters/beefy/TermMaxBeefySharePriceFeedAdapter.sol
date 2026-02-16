// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface, ITermMaxPriceFeed} from "../../priceFeeds/ITermMaxPriceFeed.sol";
import {IBeefyVaultV7} from "./IBeefyVaultV7.sol";
import {IKodiakIsland} from "./IKodiakIsland.sol";
import {BeefyLPUnderlyingReader} from "./BeefyLPUnderlyingReader.sol";

/**
 * @title TermMaxBeefySharePriceFeedAdapter
 * @notice Quote Beefy share/USD price from LP composition and token price feeds
 * @dev token0/token1 price feeds must be bound to underlying token0/token1 respectively
 */
contract TermMaxBeefySharePriceFeedAdapter is ITermMaxPriceFeed {
    using Math for *;
    using SafeCast for *;

    error GetRoundDataNotSupported();
    error InvalidPriceFeedAsset(address expected, address actual);
    error InvalidPrice(int256 answer);
    error InvalidWantAddress(address expected, address actual);

    uint256 internal constant OUTPUT_DECIMALS = 1e8;

    IBeefyVaultV7 public immutable beefyVault;
    IKodiakIsland public immutable lpToken;
    AggregatorV3Interface public immutable token0PriceFeed;
    AggregatorV3Interface public immutable token1PriceFeed;

    address public immutable asset;

    uint256 internal immutable token0PriceDenominator;
    uint256 internal immutable token1PriceDenominator;

    constructor(address _beefyVault, address _token0PriceFeed, address _token1PriceFeed) {
        beefyVault = IBeefyVaultV7(_beefyVault);
        token0PriceFeed = AggregatorV3Interface(_token0PriceFeed);
        token1PriceFeed = AggregatorV3Interface(_token1PriceFeed);

        asset = _beefyVault;

        address want = beefyVault.want();
        lpToken = IKodiakIsland(want);

        address token0 = lpToken.token0();
        address token1 = lpToken.token1();

        token0PriceDenominator = 10 ** (IERC20Metadata(token0).decimals() + token0PriceFeed.decimals());
        token1PriceDenominator = 10 ** (IERC20Metadata(token1).decimals() + token1PriceFeed.decimals());
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        string memory symbol = IERC20Metadata(asset).symbol();
        return string(abi.encodePacked("TermMax price feed: ", symbol, "/USD"));
    }

    function version() external view override returns (uint256) {
        return token0PriceFeed.version().min(token1PriceFeed.version());
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

        (uint80 roundId0, int256 answer0, uint256 startedAt0, uint256 updatedAt0, uint80 answeredInRound0) =
            token0PriceFeed.latestRoundData();
        (, int256 answer1, uint256 startedAt1, uint256 updatedAt1,) = token1PriceFeed.latestRoundData();

        roundId = roundId0;
        answeredInRound = answeredInRound0;

        if (answer0 <= 0) revert InvalidPrice(answer0);
        if (answer1 <= 0) revert InvalidPrice(answer1);

        (, uint256 token0Amount, uint256 token1Amount) =
            BeefyLPUnderlyingReader.quoteForShareAmount(address(beefyVault), 1e18);

        if (token0Amount == 0 && token1Amount == 0) {
            startedAt = startedAt0.min(startedAt1);
            updatedAt = updatedAt0.min(updatedAt1);
            answer = 0;
            return (roundId, answer, startedAt, updatedAt, answeredInRound);
        }

        uint256 token0Value = token0Amount.mulDiv(answer0.toUint256() * OUTPUT_DECIMALS, token0PriceDenominator);
        uint256 token1Value = token1Amount.mulDiv(answer1.toUint256() * OUTPUT_DECIMALS, token1PriceDenominator);

        startedAt = startedAt0.min(startedAt1);
        updatedAt = updatedAt0.min(updatedAt1);
        answer = (token0Value + token1Value).toInt256();
    }
}
