// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {VersionV2} from "../../VersionV2.sol";

contract TermMaxERC4626PriceFeed is ITermMaxPriceFeed, VersionV2 {
    using Math for *;
    using SafeCast for *;

    error GetRoundDataNotSupported();

    AggregatorV3Interface public immutable assetPriceFeed;
    address public immutable asset;
    uint256 private immutable priceDenominator;
    uint256 private immutable vaultDenominator;
    uint256 private constant PRICE_DECIMALS = 10 ** 8;

    constructor(address _underlyingPriceFeed, address _vault) {
        assetPriceFeed = AggregatorV3Interface(_underlyingPriceFeed);
        asset = _vault;
        uint8 vaultDecimals = IERC20Metadata(_vault).decimals();
        vaultDenominator = 10 ** vaultDecimals;
        uint8 underlyingDecimals = IERC20Metadata(IERC4626(_vault).asset()).decimals();
        priceDenominator = 10 ** (assetPriceFeed.decimals() + underlyingDecimals);
    }

    function decimals() public view returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        string memory symbol = IERC20Metadata(asset).symbol();
        return string(abi.encodePacked("TermMax price feed: ", symbol, "/USD"));
    }

    function version() external view returns (uint256) {
        return assetPriceFeed.version();
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
        // error to call this function because cannot get the chi (rate accumulator) at a specific round
        revert GetRoundDataNotSupported();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            assetPriceFeed.latestRoundData();
        uint256 vaultAnswer = IERC4626(asset).convertToAssets(vaultDenominator);
        answer = answer.toUint256().mulDiv(vaultAnswer * PRICE_DECIMALS, priceDenominator).toInt256();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
