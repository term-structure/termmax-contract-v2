// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title The data struct of token pair
 * @author Term Structure Labs
 */
/// @notice Date of token pair configuration 
struct TokenPairConfig {
    /// @notice The treasurer's address, which will receive protocol fee
    address treasurer;
    /// @notice The unix time of maturity date
    uint64 maturity;
    /// @notice The unix time when the market starts trading
    uint64 openTime;
    /// @notice The fee ratio when redeemming all assets after maturity
    ///         i.e. 0.01e8 means 1%
    uint32 redeemFeeRatio;
    /// @notice The fee ratio when issuing FT tokens by collateral
    ///         i.e. 0.01e8 means 1%
    uint32 issueFtFeeRatio;
    /// @notice The percentage of handling fee charged by the protocol
    ///         i.e. 0.5e8 means 50%
    uint32 protocolFeeRatio;
}

struct CurveCut{
    uint256 xtReserve;
    uint256 liqSquare;
    uint256 offset;
}

/**
 * @title The data struct of market
 * @author Term Structure Labs
 */
/// @notice Data of market's configuture
struct MarketConfig {
    /// @notice The treasurer's address, which will receive protocol fee
    address treasurer;
    /// @notice The maker's address
    address maker;
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
    /// @notice show if the market is borrow only
    bool isBorrowOnly;
    /// @notice show if the market is lend only
    bool isLendOly;
    /// @notice The curve cuts of the market
    CurveCut[] curveCuts;
}

/// @notice The parameters used to calculate curve data
struct TradeParams {
    /// @notice The token's amount
    uint256 amount;
    /// @notice The FT's balance of the market
    uint256 ftReserve;
    /// @notice The XT's balance of the market
    uint256 xtReserve;
    /// @notice The days until maturity
    uint256 daysToMaturity;
}
