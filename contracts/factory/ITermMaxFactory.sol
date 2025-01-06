// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {MarketInitialParams} from "../storage/TermMaxStorage.sol";

/**
 * @title The TermMax factory interface
 * @author Term Structure Labs
 */
interface ITermMaxFactory {
    function TERMMAX_MARKET_IMPLEMENTATION() external view returns (address);

    function gtImplements(bytes32 gtKey) external view returns (address gtImplement);

    /// @notice Set the implementations of TermMax Gearing Token contract
    function setGtImplement(string memory gtImplementName, address gtImplement) external;

    /// @notice Predict the address of token pair
    function predictMarketAddress(
        address collateral,
        address underlying,
        uint64 openTime,
        uint64 maturity
    ) external view returns (address market);

    /// @notice Deploy a new market
    function createMarket(bytes32 gtKey, MarketInitialParams memory params) external returns (address market);
}
