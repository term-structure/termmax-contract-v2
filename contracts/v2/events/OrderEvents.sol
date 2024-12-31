// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20, ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts, FeeConfig} from "../storage/TermMaxStorage.sol";
interface OrderEvents {
    /// @notice Emitted when order initialized
    /// @param market The market
    event OrderInitialized(ITermMaxMarket indexed market, address maker, CurveCuts curveCuts);

    event UpdateFeeConfig(FeeConfig feeConfig);

    /// @notice Emitted when update order
    event UpdateOrder(CurveCuts curveCuts, uint256 ftReserve, uint256 xtReserve, uint256 gtId);

    /// @notice Emitted when withdrawing FT/XT from order
    /// @param caller Who call the function
    /// @param lpFtAmt  The number of LpFT tokens burned
    /// @param lpXtAmt The number of LpXT tokens burned
    /// @param ftOutAmt The number of XT tokens received
    /// @param xtOutAmt The number of XT tokens received
    /// @param newApr New apr value with BASE_DECIMALS after do this action
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event WithdrawLiquidity(
        address indexed caller,
        uint128 lpFtAmt,
        uint128 lpXtAmt,
        uint128 ftOutAmt,
        uint128 xtOutAmt,
        int64 newApr,
        uint128 ftReserve,
        uint128 xtReserve
    );

    /// @notice Emitted when buy FT/XT using underlying token
    /// @param caller Who call the function
    /// @param recipient Who receive output tokens
    /// @param tokenOut  The token want to buy
    /// @param underlyingAmtIn The amount of underlying tokens traded
    /// @param minTokenAmtOut The minimum number of tokens to be obtained
    /// @param tokenAmtOut The number of tokens received
    /// @param feeAmt Transaction Fees
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event BuyToken(
        address indexed caller,
        address indexed recipient,
        IERC20 indexed tokenOut,
        uint underlyingAmtIn,
        uint minTokenAmtOut,
        uint tokenAmtOut,
        uint feeAmt,
        uint ftReserve,
        uint xtReserve
    );

    /// @notice Emitted when sell FT/XT
    /// @param caller Who call the function
    /// @param recipient Who receive output tokens
    /// @param tokenIn The token want to sell
    /// @param tokenAmtIn The amount of tokens traded
    /// @param minUnderlyingOut The minimum number of underlying tokens to be obtained
    /// @param underlyingAmtOut The number of underlying tokens received
    /// @param feeAmt Transaction Fees
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event SellToken(
        address indexed caller,
        address indexed recipient,
        IERC20 indexed tokenIn,
        uint tokenAmtIn,
        uint minUnderlyingOut,
        uint underlyingAmtOut,
        uint feeAmt,
        uint ftReserve,
        uint xtReserve
    );

    /// @notice Emitted when issuing FT by collateral
    /// @param caller Who call the function
    /// @param gtId The id of Gearing Token
    /// @param debtAmt The amount of debt, unit by underlying token
    /// @param ftAmt The amount of FT issued
    /// @param issueFee The amount of issuing fee, unit by FT token
    /// @param collateralData The encoded data of collateral
    event IssueFt(
        address indexed caller,
        uint256 indexed gtId,
        uint128 debtAmt,
        uint128 ftAmt,
        uint128 issueFee,
        bytes collateralData
    );
}
