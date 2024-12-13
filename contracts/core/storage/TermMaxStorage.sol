// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title The data struct of market
 * @author Term Structure Labs
 */
/// @notice Data of market's configuture
struct MarketConfig {
    /// @notice The treasurer's address, which will receive protocol fee
    address treasurer;
    /// @notice The unix time of maturity date
    uint64 maturity;
    /// @notice The unix time when the market starts trading
    uint64 openTime;
    /// @notice The current annual interest rate for borrowing in the market
    ///         i.e. 0.1e8 means 10% of the interest
    /// @dev    The annual interest rate will automatically change due to market fluctuations,
    ///         and the annual interest rate will not exceed the market initial LTV(loan to collateral) limit
    int64 apr;
    /// @notice The minimum annual interest rate for borrowing in the market
    ///         i.e. 0.05e8 means 5% of the interest
    int64 minApr;
    /// @notice The liquidity scaling factor
    ///         i.e. 0.1e8 means 0.1
    /// @dev    TODO
    uint32 lsf;
    /// @notice The lending fee ratio
    ///         i.e. 0.01e8 means 1%
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
    /// @notice The fee ratio when redeemming all assets after maturity
    ///         i.e. 0.01e8 means 1%
    uint32 redeemFeeRatio;
    /// @notice The fee ratio when issuing FT tokens by collateral
    ///         i.e. 0.01e8 means 1%
    uint32 issueFtFeeRatio;
    /// @notice The proportion of transaction fees locked in the market waiting to be released
    ///         i.e. 0.5e8 means 50%
    uint32 lockingPercentage;
    /// @notice The loan to collateral when user provide liquidity to the market
    ///         i.e. 0.9e8 means 9/10
    uint32 initialLtv;
    /// @notice The percentage of handling fee charged by the protocol
    ///         i.e. 0.5e8 means 50%
    uint32 protocolFeeRatio;
    /// @notice The flag to indicate the reward is distributed or not
    /// @dev    All locked fee will unlock after maturity
    bool rewardIsDistributed;
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
