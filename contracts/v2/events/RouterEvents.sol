// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITermMaxMarket} from "../ITermMaxMarket.sol";

interface RouterEvents {
    /// @notice Emitted when setting the market whitelist
    event UpdateMarketWhiteList(address market, bool isWhitelist);

    /// @notice Emitted when setting the swap adapter whitelist
    event UpdateSwapAdapterWhiteList(address adapter, bool isWhitelist);

    // /// @notice Emitted when swapping tokens
    // /// @param market The market's address
    // /// @param assetIn The token to swap
    // /// @param assetOut The token want to receive
    // /// @param caller Who provide input token
    // /// @param receiver Who receive output token
    // /// @param inAmt Input amount
    // /// @param outAmt Final output amount
    // /// @param minOutAmt Expected output amount
    // event Swap(
    //     ITermMaxMarket indexed market,
    //     address indexed assetIn,
    //     address indexed assetOut,
    //     address caller,
    //     address receiver,
    //     uint256 inAmt,
    //     uint256 outAmt,
    //     uint256 minOutAmt
    // );

    // /// @notice Emitted when swapping tokens
    // /// @param market The market's address
    // /// @param assetIn The token to provide liquidity
    // /// @param caller Who provide input token
    // /// @param receiver Who receive lp tokens
    // /// @param underlyingInAmt Underlying token input amount
    // /// @param lpFtOutAmt LpFT token output amount
    // /// @param lpXtOutAmt LpXT token output amount
    // event AddLiquidity(
    //     ITermMaxMarket indexed market,
    //     address indexed assetIn,
    //     address caller,
    //     address receiver,
    //     uint256 underlyingInAmt,
    //     uint256 lpFtOutAmt,
    //     uint256 lpXtOutAmt
    // );

    // /// @notice Emitted when withdrawing FT and XT token by lp tokens
    // /// @param market The market's address
    // /// @param caller Who provide lp tokens
    // /// @param receiver Who receive FT and XT token
    // /// @param lpFtInAmt LpFT token input amount
    // /// @param lpXtInAmt LpXT token input amount
    // /// @param ftOutAmt FT token output amount
    // /// @param xtOutAmt XT token output amount
    // event WithdrawLiquidityToXtFt(
    //     ITermMaxMarket indexed market,
    //     address caller,
    //     address receiver,
    //     uint256 lpFtInAmt,
    //     uint256 lpXtInAmt,
    //     uint256 ftOutAmt,
    //     uint256 xtOutAmt
    // );

    // /// @notice Emitted when withdrawing target token by lp tokens
    // /// @param market The market's address
    // /// @param assetOut The token send to receiver
    // /// @param caller Who provide lp tokens
    // /// @param receiver Who receive target token
    // /// @param lpFtInAmt LpFT token input amount
    // /// @param lpXtInAmt LpXT token input amount
    // /// @param tokenOutAmt Final target token output
    // /// @param minTokenOutAmt Expected output amount
    // event WithdrawLiquidtyToToken(
    //     ITermMaxMarket indexed market,
    //     address assetOut,
    //     address caller,
    //     address receiver,
    //     uint256 lpFtInAmt,
    //     uint256 lpXtInAmt,
    //     uint256 tokenOutAmt,
    //     uint256 minTokenOutAmt
    // );

    // /// @notice Emitted when minting GT by leverage or issueFT
    // /// @param market The market's address
    // /// @param assetIn The input token
    // /// @param caller Who provide input token
    // /// @param receiver Who receive GT
    // /// @param inAmt token input amount
    // /// @param xtInAmt XT token input amount to leverage
    // /// @param collAmt The collateral token amount in GT
    // /// @param ltv The loan to collateral of the GT
    // event IssueGt(
    //     ITermMaxMarket indexed market,
    //     address indexed assetIn,
    //     address caller,
    //     address receiver,
    //     uint256 gtId,
    //     uint256 inAmt,
    //     uint256 xtInAmt,
    //     uint256 collAmt,
    //     uint128 ltv
    // );

    // /// @notice Emitted when redeemming assets from market
    // /// @param tokenPair The address of token pair
    // /// @param caller Who provide assets
    // /// @param receiver Who receive output tokens
    // /// @param ftAmt The FT token amount
    // /// @param underlyingOutAmt The underlying token send to receiver
    // /// @param collOutAmt The collateral token send to receiver
    // event Redeem(
    //     ITermMaxTokenPair indexed tokenPair,
    //     address caller,
    //     address receiver,
    //     uint256 ftAmt,
    //     uint256 underlyingOutAmt,
    //     uint256 collOutAmt
    // );

    // /// @notice Emitted when borrowing asset from market
    // /// @param market The market's address
    // /// @param assetOut The output token
    // /// @param caller Who provide collateral asset
    // /// @param receiver Who receive output tokens
    // /// @param gtId The id of loan
    // /// @param collInAmt The collateral token input amount
    // /// @param debtAmt The debt amount of the loan
    // /// @param borrowAmt The final debt token send to receiver
    // event Borrow(
    //     ITermMaxMarket indexed market,
    //     address indexed assetOut,
    //     address caller,
    //     address receiver,
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
