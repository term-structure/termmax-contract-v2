// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PriceFeedWithERC4626} from "./PriceFeedWithERC4626.sol";
import {PriceFeedConverter} from "./PriceFeedConverter.sol";
import {PTWithPriceFeed} from "./PTWithPriceFeed.sol";

contract PriceFeedFactory {
    event PriceFeedCreated(address indexed priceFeed);

    function createPriceFeedWithERC4626(address _assetPriceFeed, address _vault) external returns (address) {
        address priceFeed = address(new PriceFeedWithERC4626(_assetPriceFeed, _vault));
        emit PriceFeedCreated(priceFeed);
        return priceFeed;
    }

    function createPriceFeedConverter(address _aTokenToBTokenPriceFeed, address _bTokenToCTokenPriceFeed)
        external
        returns (address)
    {
        address priceFeed = address(new PriceFeedConverter(_aTokenToBTokenPriceFeed, _bTokenToCTokenPriceFeed));
        emit PriceFeedCreated(priceFeed);
        return priceFeed;
    }

    function createPTWithPriceFeed(address _pendlePYLpOracle, address _market, uint32 _duration, address _priceFeed)
        external
        returns (address)
    {
        address priceFeed = address(new PTWithPriceFeed(_pendlePYLpOracle, _market, _duration, _priceFeed));
        emit PriceFeedCreated(priceFeed);
        return priceFeed;
    }
}
