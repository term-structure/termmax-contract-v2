// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";

interface RouterEvents {
    /// @notice Emitted when setting the market whitelist
    event UpdateMarketWhiteList(address market, bool isWhitelist);

    /// @notice Emitted when setting the swap adapter whitelist
    event UpdateSwapAdapterWhiteList(address adapter, bool isWhitelist);

    event SwapExactTokenToToken(
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        address caller,
        address recipient,
        ITermMaxOrder[] orders,
        uint128[] tradingAmts,
        uint256 actualTokenOut
    );

    event IssueGt(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint128 debtTokenAmtIn,
        uint128 xtAmtIn,
        uint128 ltv,
        bytes collData
    );

    event Borrow(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint256 collInAmt,
        uint128 actualDebtAmt,
        uint128 borrowAmt
    );

    // /// @notice Emitted when redeemming assets from market
    // /// @param tokenPair The address of token pair
    // /// @param caller Who provide assets
    // /// @param recipient Who receive output tokens
    // /// @param ftAmt The FT token amount
    // /// @param underlyingOutAmt The underlying token send to recipient
    // /// @param collOutAmt The collateral token send to recipient
    // event Redeem(
    //     ITermMaxTokenPair indexed tokenPair,
    //     address caller,
    //     address recipient,
    //     uint256 ftAmt,
    //     uint256 underlyingOutAmt,
    //     uint256 collOutAmt
    // );

    // /// @notice Emitted when borrowing asset from market
    // /// @param market The market's address
    // /// @param assetOut The output token
    // /// @param caller Who provide collateral asset
    // /// @param recipient Who receive output tokens
    // /// @param gtId The id of loan
    // /// @param collInAmt The collateral token input amount
    // /// @param debtAmt The debt amount of the loan
    // /// @param borrowAmt The final debt token send to recipient
    // event Borrow(
    //     ITermMaxMarket indexed market,
    //     address indexed assetOut,
    //     address caller,
    //     address recipient,
    //     uint256 gtId,
    //     uint256 collInAmt,
    //     uint256 debtAmt,
    //     uint256 borrowAmt
    // );

    // /// @notice Emitted when repaying loan
    // /// @param market The market's address
    // /// @param isRepayFt Repay using FT or underlying token
    // /// @param assetIn The input token to repay loan
    // /// @param gtId The id of loan
    // /// @param inAmt The input amount
    // event Repay(
    //     ITermMaxMarket indexed market,
    //     bool indexed isRepayFt,
    //     address indexed assetIn,
    //     uint256 gtId,
    //     uint256 inAmt
    // );
}
