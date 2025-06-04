// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {OrderConfig, MarketConfig, CurveCuts, FeeConfig} from "./storage/TermMaxStorage.sol";
import {ISwapCallback} from "./ISwapCallback.sol";

/**
 * @title TermMax Order interface
 * @author Term Structure Labs
 */
interface ITermMaxOrder {
    /// @notice Initialize the token and configuration of the order
    /// @param maker The maker
    /// @param tokens The tokens
    /// @param gt The Gearing Token
    /// @param maxXtReserve The maximum reserve of XT token
    /// @param curveCuts The curve cuts
    /// @param marketConfig The market configuration
    /// @dev Only factory will call this function once when deploying new market
    function initialize(
        address maker,
        IERC20[3] memory tokens,
        IGearingToken gt,
        uint256 maxXtReserve,
        ISwapCallback trigger,
        CurveCuts memory curveCuts,
        MarketConfig memory marketConfig
    ) external;

    /// @notice Return the configuration
    function orderConfig() external view returns (OrderConfig memory);

    /// @notice Return the maker
    function maker() external view returns (address);

    /// @notice Set the market configuration
    /// @param newOrderConfig New order configuration
    /// @param ftChangeAmt Change amount of FT reserve
    /// @param xtChangeAmt Change amount of XT reserve
    function updateOrder(OrderConfig memory newOrderConfig, int256 ftChangeAmt, int256 xtChangeAmt) external;

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external;

    function updateFeeConfig(FeeConfig memory newFeeConfig) external;

    /// @notice Return the token reserves
    function tokenReserves() external view returns (uint256 ftReserve, uint256 xtReserve);

    /// @notice Return the tokens in TermMax Market
    /// @return market The market
    function market() external view returns (ITermMaxMarket market);

    /// @notice Return the current apr of the amm order book
    /// @return lendApr Lend APR
    /// @return borrowApr Borrow APR
    function apr() external view returns (uint256 lendApr, uint256 borrowApr);

    /// @notice Swap exact token to token
    /// @param tokenIn The token want to swap
    /// @param tokenOut The token want to receive
    /// @param recipient Who receive output tokens
    /// @param tokenAmtIn The number of tokenIn tokens input
    /// @param minTokenOut Minimum number of tokenOut token outputs required
    /// @param deadline The timestamp after which the transaction will revert
    /// @return netOut The actual number of tokenOut tokens received
    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtIn,
        uint128 minTokenOut,
        uint256 deadline
    ) external returns (uint256 netOut);

    /// @notice Swap token to exact token
    /// @param tokenIn The token want to swap
    /// @param tokenOut The token want to receive
    /// @param recipient Who receive output tokens
    /// @param tokenAmtOut The number of tokenOut tokens output
    /// @param maxTokenIn Maximum number of tokenIn token inputs required
    /// @param deadline The timestamp after which the transaction will revert
    /// @return netIn The actual number of tokenIn tokens input
    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtOut,
        uint128 maxTokenIn,
        uint256 deadline
    ) external returns (uint256 netIn);

    /// @notice Suspension of market trading
    function pause() external;

    /// @notice Open Market Trading
    function unpause() external;
}
