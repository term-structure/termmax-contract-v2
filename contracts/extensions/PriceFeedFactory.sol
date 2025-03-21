// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PriceFeedWithERC4626} from "./PriceFeedWithERC4626.sol";
import {PriceFeedConverter} from "./PriceFeedConverter.sol";
import {PTWithPriceFeed} from "./PTWithPriceFeed.sol";

contract PriceFeedFactory {
    function createPriceFeedWithERC4626(address _assetPriceFeed, address _vault) external returns (address) {
        return address(new PriceFeedWithERC4626(_assetPriceFeed, _vault));
    }

    function createPriceFeedConverter(address _aTokenToBTokenPriceFeed, address _bTokenToCTokenPriceFeed)
        external
        returns (address)
    {
        return address(new PriceFeedConverter(_aTokenToBTokenPriceFeed, _bTokenToCTokenPriceFeed));
    }

    function createPTWithPriceFeed(address _pendlePYLpOracle, address _market, uint32 _duration, address _priceFeed)
        external
        returns (address)
    {
        return address(new PTWithPriceFeed(_pendlePYLpOracle, _market, _duration, _priceFeed));
    }
}
