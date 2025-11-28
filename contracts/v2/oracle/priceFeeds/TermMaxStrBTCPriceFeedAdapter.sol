// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {VersionV2} from "../../VersionV2.sol";

contract TermMaxStrBTCPriceFeedAdapter is ITermMaxPriceFeed, VersionV2 {
    using Math for *;
    using SafeCast for *;

    AggregatorV3Interface public immutable strBTCReserveFeed;
    AggregatorV3Interface public immutable btcPriceFeed;

    uint256 immutable priceDenominator;
    address public immutable asset;
    uint256 constant PRICE_DENOMINATOR = 10 ** 8;
    uint8 constant BTC_DECIMALS = 8;

    error InvalidDecimals();

    constructor(address _strBTCReserveFeed, address _btcPriceFeed, address _asset) {
        asset = _asset;
        strBTCReserveFeed = AggregatorV3Interface(_strBTCReserveFeed);
        btcPriceFeed = AggregatorV3Interface(_btcPriceFeed);
        // Ensure both strBTC price feeds and the asset have 8 decimals
        require(AggregatorV3Interface(_strBTCReserveFeed).decimals() == BTC_DECIMALS, InvalidDecimals());
        require(IERC20Metadata(_asset).decimals() == BTC_DECIMALS, InvalidDecimals());

        priceDenominator = 10 ** btcPriceFeed.decimals();
    }

    function decimals() public view returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        string memory symbol = IERC20Metadata(asset).symbol();
        return string(abi.encodePacked("TermMax price feed: ", symbol, "/USD"));
    }

    function version() external view returns (uint256) {
        return strBTCReserveFeed.version();
    }

    function getRoundData(uint80 /* _roundId */ )
        external
        view
        returns (
            uint80, /* roundId */
            int256, /* answer */
            uint256, /* startedAt */
            uint256, /* updatedAt */
            uint80 /* answeredInRound */
        )
    {
        return latestRoundData();
    }

    function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80) {
        /// @dev The strBTCReserveFeed answer is the reserve of BTC coins
        (uint80 roundId, int256 reserves, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            strBTCReserveFeed.latestRoundData();
        // Get total supply of strBTC token
        uint256 totalSupply = IERC20Metadata(asset).totalSupply();
        // Calculate strBTC to BTC price = PRICE_DENOMINATOR * reserve / totalSupply decimals are all 8
        uint256 strBtcToBtc = reserves.toUint256().mulDiv(PRICE_DENOMINATOR, totalSupply);
        /// @dev Get BTC to USD price
        (, int256 answer, uint256 startedAt2, uint256 updatedAt2,) = btcPriceFeed.latestRoundData();
        // tokenPrice = answer * answer2
        answer = answer.toUint256().mulDiv(strBtcToBtc, priceDenominator).toInt256();
        return (roundId, answer, startedAt.min(startedAt2), updatedAt.min(updatedAt2), answeredInRound);
    }
}
