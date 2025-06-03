// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MathLib} from "contracts/v1/lib/MathLib.sol";

contract PriceFeedWithERC4626 is AggregatorV3Interface {
    using MathLib for *;

    error GetRoundDataNotSupported();

    AggregatorV3Interface public immutable assetPriceFeed;
    IERC4626 public immutable vault;
    int256 immutable priceDemonitor;
    uint256 immutable vaultDemonitor;

    constructor(address _assetPriceFeed, address _vault) {
        assetPriceFeed = AggregatorV3Interface(_assetPriceFeed);
        vault = IERC4626(_vault);
        vaultDemonitor = 10 ** vault.decimals();
        uint256 assetDemonitor = 10 ** IERC20Metadata(vault.asset()).decimals();
        priceDemonitor = int256(10 ** assetPriceFeed.decimals()) * int256(assetDemonitor);
    }

    function decimals() public view returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        return string(abi.encodePacked("Price Feed for ", vault.name()));
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
        uint256 vaultAnswer = vault.previewRedeem(vaultDemonitor).min(vault.convertToAssets(vaultDemonitor));
        answer = answer * int256(vaultAnswer) * int256((10 ** decimals())) / priceDemonitor;
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
