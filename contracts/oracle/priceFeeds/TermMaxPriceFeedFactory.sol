// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxERC4626PriceFeed} from "./TermMaxERC4626PriceFeed.sol";
import {TermMaxPriceFeedConverter} from "./TermMaxPriceFeedConverter.sol";
import {TermMaxPTPriceFeed} from "./TermMaxPTPriceFeed.sol";

contract TermMaxPriceFeedFactory {
    event PriceFeedCreated(address indexed priceFeed);

    function createPriceFeedWithERC4626(address _assetPriceFeed, address _vault) external returns (address) {
        address priceFeed = address(new TermMaxERC4626PriceFeed(_assetPriceFeed, _vault));
        emit PriceFeedCreated(priceFeed);
        return priceFeed;
    }

    function createPriceFeedConverter(
        address _aTokenToBTokenPriceFeed,
        address _bTokenToCTokenPriceFeed,
        address _asset
    ) external returns (address) {
        address priceFeed =
            address(new TermMaxPriceFeedConverter(_aTokenToBTokenPriceFeed, _bTokenToCTokenPriceFeed, _asset));
        emit PriceFeedCreated(priceFeed);
        return priceFeed;
    }

    function createPTWithPriceFeed(address _pendlePYLpOracle, address _market, uint32 _duration, address _priceFeed)
        external
        returns (address)
    {
        address priceFeed = address(new TermMaxPTPriceFeed(_pendlePYLpOracle, _market, _duration, _priceFeed));
        emit PriceFeedCreated(priceFeed);
        return priceFeed;
    }
}
