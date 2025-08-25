// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxERC4626PriceFeed} from "../oracle/priceFeeds/TermMaxERC4626PriceFeed.sol";
import {TermMaxPriceFeedConverter} from "../oracle/priceFeeds/TermMaxPriceFeedConverter.sol";
import {TermMaxPTPriceFeed} from "../oracle/priceFeeds/TermMaxPTPriceFeed.sol";
import {FactoryEventsV2} from "../events/FactoryEventsV2.sol";
import {VersionV2} from "../VersionV2.sol";

/**
 * @title TermMax Price Feed Factory V2
 * @author Term Structure Labs
 * @notice Factory contract for creating various types of price feeds in the TermMax V2 protocol
 * @dev Provides standardized creation methods for ERC4626 vault price feeds, price feed converters, and Pendle PT price feeds
 * All price feeds implement the ITermMaxPriceFeed interface for consistency
 */
contract TermMaxPriceFeedFactoryV2 is VersionV2 {
    /**
     * @notice Creates a price feed for ERC4626 vaults
     * @dev Deploys a TermMaxERC4626PriceFeed that calculates vault token prices based on the underlying asset price and vault exchange rate
     * @param _assetPriceFeed The address of the underlying asset's price feed (e.g., USDC/USD feed)
     * @param _vault The address of the ERC4626 vault contract
     * @return The address of the newly deployed ERC4626 price feed
     * @custom:usage Used for vault tokens like stETH, rETH, or other yield-bearing assets that implement ERC4626
     */
    function createPriceFeedWithERC4626(address _assetPriceFeed, address _vault) external returns (address) {
        address priceFeed = address(new TermMaxERC4626PriceFeed(_assetPriceFeed, _vault));
        emit FactoryEventsV2.PriceFeedCreated(priceFeed);
        return priceFeed;
    }

    /**
     * @notice Creates a price feed converter that chains two price feeds together
     * @dev Deploys a TermMaxPriceFeedConverter that multiplies prices from two feeds (A->B and B->C to get A->C)
     * @param _aTokenToBTokenPriceFeed The first price feed in the chain (token A to token B)
     * @param _bTokenToCTokenPriceFeed The second price feed in the chain (token B to token C)
     * @param _asset The address of the asset being priced (token A)
     * @return The address of the newly deployed price feed converter
     * @custom:example Converting stETH to USD: stETH->ETH feed × ETH->USD feed = stETH->USD price
     * @custom:precision Final price maintains 8 decimal precision regardless of input feed decimals
     */
    function createPriceFeedConverter(
        address _aTokenToBTokenPriceFeed,
        address _bTokenToCTokenPriceFeed,
        address _asset
    ) external returns (address) {
        address priceFeed =
            address(new TermMaxPriceFeedConverter(_aTokenToBTokenPriceFeed, _bTokenToCTokenPriceFeed, _asset));
        emit FactoryEventsV2.PriceFeedCreated(priceFeed);
        return priceFeed;
    }

    /**
     * @notice Creates a price feed for Pendle Principal Tokens (PT)
     * @dev Deploys a TermMaxPTPriceFeed that calculates PT prices using Pendle's oracle system and underlying asset prices
     * @param _pendlePYLpOracle The address of the Pendle PY LP oracle contract
     * @param _market The address of the Pendle market contract for the specific PT
     * @param _duration The TWAP duration in seconds for price calculation stability
     * @param _priceFeed The price feed for the underlying asset that the PT represents
     * @return The address of the newly deployed PT price feed
     * @custom:usage Used for Pendle Principal Tokens like PT-stETH, PT-USDC, etc.
     * @custom:security Includes oracle readiness checks to ensure price feed reliability
     * @custom:formula PT Price = PT Rate in SY × SY Price / PT to Asset Rate Base
     */
    function createPTWithPriceFeed(address _pendlePYLpOracle, address _market, uint32 _duration, address _priceFeed)
        external
        returns (address)
    {
        address priceFeed = address(new TermMaxPTPriceFeed(_pendlePYLpOracle, _market, _duration, _priceFeed));
        emit FactoryEventsV2.PriceFeedCreated(priceFeed);
        return priceFeed;
    }
}
