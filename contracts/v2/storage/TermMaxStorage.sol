// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title The data struct of token pair
 * @author Term Structure Labs
 */

struct CurveCut {
    uint256 xtReserve;
    uint256 liqSquare;
    uint256 offset;
}

struct FeeConfig {
    /// @notice The unix time of maturity date
    uint32 lendFeeRatio;
    /// @notice The minmally notional lending fee ratio
    ///         i.e. 0.01e8 means 1%
    uint32 minNLendFeeR;
    /// @notice The borrowing fee ratio
    ///         i.e. 0.01e8 means 1%
    uint32 borrowFeeRatio;
    /// @notice The minmally notional borrowing fee ratio
    ///         i.e. 0.01e8 means 1%
    uint32 minNBorrowFeeR;
    /// @notice The fee ratio when issuing FT tokens by collateral
    ///         i.e. 0.01e8 means 1%
    uint32 issueFtFeeRatio;
    uint32 redeemFeeRatio;
}

struct CurveCuts {
    /// @notice The curve cuts of the market to lend
    CurveCut[] lendCurveCuts;
    /// @notice The curve cuts of the market to borrow
    CurveCut[] borrowCurveCuts;
}

struct MarketConfig {
    /// @notice The treasurer's address, which will receive protocol fee
    address treasurer;
    /// @notice The unix time of maturity date
    uint64 maturity;
    /// @notice The unix time when the market starts trading
    uint64 openTime;
    /// @notice The fee ratio when tradings with the market and orders
    FeeConfig feeConfig;
}
