// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOracle} from "../oracle/IOracle.sol";
import {ISwapCallback} from "../ISwapCallback.sol";

/**
 * @title The data struct of token pair
 * @author Term Structure Labs
 */
struct CurveCut {
    uint256 xtReserve;
    uint256 liqSquare;
    int256 offset;
}

struct FeeConfig {
    /// @notice The lending fee ratio taker
    ///         i.e. 0.01e8 means 1%
    uint32 lendTakerFeeRatio;
    /// @notice The lending fee ratio for maker
    ///         i.e. 0.01e8 means 1%
    uint32 lendMakerFeeRatio;
    /// @notice The borrowing fee ratio for taker
    ///         i.e. 0.01e8 means 1%
    uint32 borrowTakerFeeRatio;
    /// @notice The borrowing fee ratio for maker
    ///         i.e. 0.01e8 means 1%
    uint32 borrowMakerFeeRatio;
    /// @notice The fee ratio when minting GT tokens by collateral
    ///         i.e. 0.01e8 means 1%
    uint32 mintGtFeeRatio;
    /// @notice The fee ref when minting GT tokens by collateral
    ///         i.e. 0.01e8 means 1%
    uint32 mintGtFeeRef;
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
    /// @notice The fee ratio when tradings with the market and orders
    FeeConfig feeConfig;
}

struct LoanConfig {
    /// @notice The oracle aggregator
    IOracle oracle;
    /// @notice The debt liquidation threshold
    ///         If the loan to collateral is greater than or equal to this value,
    ///         it will be liquidated
    ///         i.e. 0.9e8 means debt value is the 90% of collateral value
    uint32 liquidationLtv;
    /// @notice Maximum loan to collateral when borrowing
    ///         i.e. 0.85e8 means debt value is the 85% of collateral value
    uint32 maxLtv;
    /// @notice The flag to indicate debt is liquidatable or not
    /// @dev    If liquidatable is false, the collateral can only be delivered after maturity
    bool liquidatable;
}

/// @notice Data of Gearing Token's configuturation
struct GtConfig {
    /// @notice The address of collateral token
    address collateral;
    /// @notice The debtToken(debt) token
    IERC20Metadata debtToken;
    /// @notice The bond token
    IERC20 ft;
    /// @notice The treasurer's address, which will receive protocol reward while liquidation
    address treasurer;
    /// @notice The unix time of maturity date
    uint64 maturity;
    /// @notice The configuration of oracle, ltv and liquidation
    LoanConfig loanConfig;
}

struct OrderConfig {
    CurveCuts curveCuts;
    uint256 gtId;
    uint256 maxXtReserve;
    ISwapCallback swapTrigger;
    FeeConfig feeConfig;
}

struct MarketInitialParams {
    /// @notice The address of collateral token
    address collateral;
    /// @notice The debtToken(debt) token
    IERC20Metadata debtToken;
    /// @notice The admin address
    address admin;
    /// @notice The implementation of TermMax Gearing Token contract
    address gtImplementation;
    /// @notice The configuration of market
    MarketConfig marketConfig;
    /// @notice The configuration of loan
    LoanConfig loanConfig;
    /// @notice The encoded parameters to initialize GT implementation contract
    bytes gtInitalParams;
    string tokenName;
    string tokenSymbol;
}

struct VaultInitialParams {
    address admin;
    address curator;
    uint256 timelock;
    IERC20 asset;
    uint256 maxCapacity;
    string name;
    string symbol;
    uint64 performanceFeeRate;
}
