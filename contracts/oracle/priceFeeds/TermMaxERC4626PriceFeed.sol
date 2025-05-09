// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ITermMaxPriceFeed, AggregatorV3Interface} from "./ITermMaxPriceFeed.sol";
import {MathLib} from "contracts/lib/MathLib.sol";

contract TermMaxERC4626PriceFeed is ITermMaxPriceFeed {
    using MathLib for *;

    error GetRoundDataNotSupported();

    AggregatorV3Interface public immutable assetPriceFeed;
    address public immutable asset;
    int256 immutable priceDemonitor;
    uint256 immutable vaultDemonitor;

    constructor(address _assetPriceFeed, address _asset) {
        (, int256 answer,,,) = AggregatorV3Interface(_assetPriceFeed).latestRoundData();
        assetPriceFeed = AggregatorV3Interface(_assetPriceFeed);
        asset = _asset;
        vaultDemonitor = 10 ** IERC4626(asset).decimals();
        uint256 assetDemonitor = 10 ** IERC20Metadata(asset).decimals();
        priceDemonitor = int256(10 ** assetPriceFeed.decimals()) * int256(assetDemonitor);
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
        uint256 vaultAnswer =
            IERC4626(asset).previewRedeem(vaultDemonitor).min(IERC4626(asset).convertToAssets(vaultDemonitor));
        answer = answer * int256(vaultAnswer) * int256((10 ** decimals())) / priceDemonitor;
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
