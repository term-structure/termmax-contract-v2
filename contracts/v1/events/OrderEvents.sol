// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20, ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts, FeeConfig} from "../storage/TermMaxStorage.sol";
import {ISwapCallback} from "../ISwapCallback.sol";

/**
 * @title Order Events Interface
 * @notice Events emitted by the TermMax order operations
 */
interface OrderEvents {
    /**
     * @notice Emitted when an order is initialized
     * @param market The market address
     * @param maker The maker address
     * @param maxXtReserve The maximum XT reserve
     * @param swapTrigger The swap callback contract
     * @param curveCuts The curve parameters
     */
    event OrderInitialized(
        ITermMaxMarket indexed market,
        address indexed maker,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger,
        CurveCuts curveCuts
    );

    /**
     * @notice Emitted when the fee configuration is updated
     * @param feeConfig The new fee configuration
     */
    event UpdateFeeConfig(FeeConfig feeConfig);

    /**
     * @notice Emitted when an order is updated
     * @param curveCuts The new curve parameters
     * @param ftChangeAmt The change in FT reserves
     * @param xtChangeAmt The change in XT reserves
     * @param gtId The global trade ID
     * @param maxXtReserve The new maximum XT reserve
     * @param swapTrigger The swap callback contract
     */
    event UpdateOrder(
        CurveCuts curveCuts,
        int256 ftChangeAmt,
        int256 xtChangeAmt,
        uint256 gtId,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger
    );

    /**
     * @notice Emitted when a swap occurs
     * @param tokenIn The token being swapped in
     * @param tokenOut The token being swapped out
     * @param caller The address initiating the swap
     * @param recipient The address receiving the swapped tokens
     * @param tokenAmtIn The amount of tokenIn being swapped
     * @param netTokenOut The amount of tokenOut being received
     * @param feeAmt The amount of fee being paid
     */
    event SwapExactTokenToToken(
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        address caller,
        address recipient,
        uint128 tokenAmtIn,
        uint128 netTokenOut,
        uint128 feeAmt
    );

    /**
     * @notice Emitted when a swap occurs
     * @param tokenIn The token being swapped in
     * @param tokenOut The token being swapped out
     * @param caller The address initiating the swap
     * @param recipient The address receiving the swapped tokens
     * @param tokenAmtOut The amount of tokenOut being received
     * @param netTokenIn The amount of tokenIn being swapped
     * @param feeAmt The amount of fee being paid
     */
    event SwapTokenToExactToken(
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        address caller,
        address recipient,
        uint128 tokenAmtOut,
        uint128 netTokenIn,
        uint128 feeAmt
    );

    /**
     * @notice Emitted when assets are withdrawn
     * @param token The token being withdrawn
     * @param caller The address initiating the withdrawal
     * @param recipient The address receiving the withdrawn tokens
     * @param amount The amount of tokens being withdrawn
     */
    event WithdrawAssets(IERC20 indexed token, address indexed caller, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when maker ownership is transferred
     * @param oldMaker The address of the previous maker
     * @param newMaker The address of the new maker
     */
    event MakerOwnershipTransferred(address oldMaker, address newMaker);
}
