// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {TermMaxOndoPriceFeedAdapter} from "./TermMaxOndoPriceFeedAdapter.sol";

/**
 * @notice Interface for TermMaxPriceFeedFactoryV2 with only the required method
 */
interface IPriceFeedFactory {
    function createPriceFeedConverter(
        address _aTokenToBTokenPriceFeed,
        address _bTokenToCTokenPriceFeed,
        address _asset
    ) external returns (address);
}

/**
 * @title TermMaxOndoPriceFeedAdapterFactory
 * @notice Factory contract for deploying TermMaxOndoPriceFeedAdapter instances and converters
 * @dev The Ondo oracle address is set once in the factory and used for all deployed adapters
 */
contract TermMaxOndoPriceFeedAdapterFactory {
    /// @notice The Ondo SyntheticSharesOracle contract address used for all adapters
    address public immutable ondoOracle;

    /// @notice The TermMaxPriceFeedFactoryV2 used for creating converters
    IPriceFeedFactory public immutable priceFeedFactory;

    /// @notice Mapping of asset address to deployed adapter address
    mapping(address => address) public adapters;

    /// @notice Mapping of asset address to deployed converter address (asset/USD)
    mapping(address => address) public converters;

    /// @notice Emitted when a new adapter is deployed
    event AdapterDeployed(address indexed asset, address indexed adapter);

    /// @notice Emitted when a new converter is deployed
    event ConverterDeployed(address indexed asset, address indexed converter);

    error AdapterAlreadyExists();
    error ZeroAddress();

    /**
     * @notice Construct the factory with the Ondo oracle address and price feed factory
     * @param _ondoOracle The Ondo SyntheticSharesOracle contract address
     * @param _priceFeedFactory The TermMaxPriceFeedFactoryV2 contract address
     */
    constructor(address _ondoOracle, address _priceFeedFactory) {
        if (_ondoOracle == address(0) || _priceFeedFactory == address(0)) revert ZeroAddress();
        ondoOracle = _ondoOracle;
        priceFeedFactory = IPriceFeedFactory(_priceFeedFactory);
    }

    /**
     * @notice Deploy a new TermMaxOndoPriceFeedAdapter for a given asset
     * @param asset The GM asset address to create an adapter for
     * @return adapter The address of the newly deployed adapter
     */
    function deployAdapter(address asset) public returns (address adapter) {
        if (asset == address(0)) revert ZeroAddress();
        if (adapters[asset] != address(0)) revert AdapterAlreadyExists();

        adapter = address(new TermMaxOndoPriceFeedAdapter(ondoOracle, asset));
        adapters[asset] = adapter;

        emit AdapterDeployed(asset, adapter);
    }

    /**
     * @notice Deploy a converter for asset/USD using the adapter and an external price feed
     * @param asset The GM asset address (e.g., TSLAON)
     * @param assetUSDPriceFeed The price feed for the underlying asset (e.g., TSLA/USD)
     * @return converter The address of the newly deployed converter
     * @dev This will deploy the adapter first if it doesn't exist yet
     */
    function deployConverter(address asset, address assetUSDPriceFeed) external returns (address converter) {
        if (asset == address(0) || assetUSDPriceFeed == address(0)) revert ZeroAddress();

        // Deploy adapter if not already deployed
        address adapter = adapters[asset];
        if (adapter == address(0)) {
            adapter = deployAdapter(asset);
        }

        // Deploy converter: adapter (sValue) × assetUSDPriceFeed (e.g., TSLA/USD) = asset/USD
        converter = priceFeedFactory.createPriceFeedConverter(adapter, assetUSDPriceFeed, asset);
        converters[asset] = converter;

        emit ConverterDeployed(asset, converter);
    }

    /**
     * @notice Get the adapter address for a given asset
     * @param asset The GM asset address
     * @return The adapter address, or address(0) if not deployed
     */
    function getAdapter(address asset) external view returns (address) {
        return adapters[asset];
    }

    /**
     * @notice Get the converter address for a given asset
     * @param asset The GM asset address
     * @return The converter address, or address(0) if not deployed
     */
    function getConverter(address asset) external view returns (address) {
        return converters[asset];
    }
}
