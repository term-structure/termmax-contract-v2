// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IMintableERC20, IERC20} from "../tokens/IMintableERC20.sol";
import {IGearingToken} from "../tokens/IGearingToken.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {MarketConfig} from "../storage/TermMaxStorage.sol";

interface MarketEvents {
    /// @notice Emitted when market initialized
    /// @param collateral Collateral token
    /// @param underlying Underlying token
    /// @param openTime The unix time when the market starts trading
    /// @param maturity The unix time of maturity date
    /// @param ft TermMax Market FT
    /// @param xt TermMax Market XT
    /// @param gt Gearing token
    event MarketInitialized(
        address indexed collateral,
        IERC20 indexed underlying,
        uint64 openTime,
        uint64 maturity,
        IMintableERC20 ft,
        IMintableERC20 xt,
        IGearingToken gt
    );

    /// @notice Emitted when market config is updated
    event UpdateMarketConfig(MarketConfig config);

    /// @notice Emitted when doing leverage
    /// @param loanReceiver Who call the function
    /// @param gtReceiver Who receive the Gearing Token
    /// @param gtId The id of Gearing Token
    /// @param debtAmt The amount of debt, unit by underlying token
    /// @param collateralData The encoded data of collateral
    event MintGt(
        address indexed loanReceiver,
        address indexed gtReceiver,
        uint256 indexed gtId,
        uint128 debtAmt,
        bytes collateralData
    );

    /// @notice Emitted when issuing FT by collateral
    /// @param caller Who call the function
    /// @param recipient Who receive the tokens
    /// @param gtId The id of Gearing Token
    /// @param debtAmt The amount of debt, unit by underlying token
    /// @param ftAmt The amount of FT issued
    /// @param issueFee The amount of issuing fee, unit by FT token
    /// @param collateralData The encoded data of collateral
    event IssueFt(
        address indexed caller,
        address indexed recipient,
        uint256 indexed gtId,
        uint128 debtAmt,
        uint128 ftAmt,
        uint128 issueFee,
        bytes collateralData
    );

    /// @notice Emitted when issuing FT by existed Gearing Token
    /// @param caller Who call the function
    /// @param recipient Who receive the tokens
    /// @param gtId The id of Gearing Token
    /// @param debtAmt The amount of debt, unit by underlying token
    /// @param ftAmt The amount of FT issued
    /// @param issueFee The amount of issuing fee, unit by FT token
    event IssueFtByExistedGt(
        address indexed caller,
        address indexed recipient,
        uint256 indexed gtId,
        uint128 debtAmt,
        uint128 ftAmt,
        uint128 issueFee
    );

    /// @notice Emitted when redeeming tokens
    /// @param caller Who call the function
    /// @param recipient Who receive the tokens
    /// @param proportion The proportion of underlying token and collateral should be deliveried
    ///                   base 1e16 decimals
    /// @param underlyingAmt The amount of underlying received
    /// @param feeAmt Redeemming Fees
    /// @param deliveryData The encoded data of collateral received
    event Redeem(
        address indexed caller,
        address indexed recipient,
        uint128 proportion,
        uint128 underlyingAmt,
        uint128 feeAmt,
        bytes deliveryData
    );

    /// @notice Emitted when creating an order
    /// @param maker The maker of the order
    /// @param order The order
    event CreateOrder(address indexed maker, ITermMaxOrder indexed order);
}
