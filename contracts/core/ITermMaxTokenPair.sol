// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {TokenPairConfig} from "./storage/TermMaxStorage.sol";

/**
 * @title TermMax Token Pair interface
 * @author Term Structure Labs
 */
interface ITermMaxTokenPair {
    /// @notice Error for invalid unix time parameters
    error InvalidTime(uint64 openTime, uint64 maturity);
    /// @notice Error for the collateral and underlying are the same token
    error CollateralCanNotEqualUnderlyinng();
    /// @notice Error for it is not the opening trading day yet
    error TermIsNotOpen();
    /// @notice Error for the maturity day has been reached
    error TermWasClosed();
    /// @notice Error for redeeming before the liquidation window
    error CanNotRedeemBeforeFinalLiquidationDeadline(
        uint256 liquidationDeadline
    );

    /// @notice Emitted when market initialized
    /// @param collateral Collateral token
    /// @param underlying Underlying token
    /// @param openTime The unix time when the market starts trading
    /// @param maturity The unix time of maturity date
    /// @param ft TermMax Market FT
    /// @param xt TermMax Market XT
    /// @param gt Gearing token
    event TokenPairInitialized(
        address indexed collateral,
        IERC20 indexed underlying,
        uint64 openTime,
        uint64 maturity,
        IMintableERC20 ft,
        IMintableERC20 xt,
        IGearingToken gt
    );

    /// @notice Emitted when market config is updated
    event UpdateTokenPairConfig(TokenPairConfig config);

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

    /// @notice Emitted when redeeming tokens
    /// @param caller Who call the function
    /// @param proportion The proportion of underlying token and collateral should be deliveried
    ///                   base 1e16 decimals
    /// @param underlyingAmt The amount of underlying received
    /// @param feeAmt Redeemming Fees
    /// @param deliveryData The encoded data of collateral received
    event Redeem(
        address indexed caller,
        uint128 proportion,
        uint128 underlyingAmt,
        uint128 feeAmt,
        bytes deliveryData
    );

    /// @notice Initialize the token and configuration of the market
    /// @param admin Administrator address for configuring parameters such as transaction fees
    /// @param collateral_ Collateral token
    /// @param underlying_ Underlying Token(debt)
    /// @param ft_ TermMax FT
    /// @param xt_ TermMax XT
    /// @param gt_ TermMax Gearing Token
    /// @param config_ Configuration of market
    /// @dev Only factory will call this function once when deploying new market
    function initialize(
        address admin,
        address collateral_,
        IERC20 underlying_,
        IMintableERC20 ft_,
        IMintableERC20 xt_,
        IGearingToken gt_,
        TokenPairConfig memory config_
    ) external;

    /// @notice Return the configuration
    function config() external view returns (TokenPairConfig memory);

    /// @notice Set the market configuration
    function updateTokenPairConfig(TokenPairConfig calldata newConfig) external;

    /// @notice Return the tokens in TermMax Market
    /// @return ft Fixed-rate Token(bond token). Earning Fixed Income with High Certainty
    /// @return xt Intermediary Token for Collateralization and Leveragin
    /// @return gt Gearing Token
    /// @return collateral Collateral token
    /// @return underlying Underlying Token(debt)
    function tokens()
        external
        view
        returns (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IGearingToken gt,
            address collateral,
            IERC20 underlying
        );

    /// @notice Mint FT and XT tokens by underlying token.
    ///         No price slippage or handling fees.
    /// @param underlyingAmt Amount of underlying token want to lock
    function mintFtAndXt(address caller, address receiver, uint256 underlyingAmt) external;

    /// @notice redeem FT and XT to underlying token.
    ///         No price slippage or handling fees.
    /// @param underlyingAmt Amount of underlying token want to redeem
    function redeemFtAndXtToUnderlying(address caller, address receiver, uint256 underlyingAmt) external;

    /// @notice Using collateral to issue FT tokens.
    ///         Caller will get FT(bond) tokens equal to the debt amount subtract issue fee
    /// @param debt The amount of debt, unit by underlying token
    /// @param collateralData The encoded data of collateral
    /// @return gtId The id of Gearing Token
    ///
    function issueFt(
        uint128 debt,
        bytes calldata collateralData
    ) external returns (uint256 gtId, uint128 ftOutAmt);

    /// @notice Flash loan underlying token for leverage
    /// @param receiver Who will receive Gearing Token
    /// @param xtAmt The amount of XT token.
    ///              The caller will receive an equal amount of underlying token by flash loan.
    /// @param callbackData The data of flash loan callback
    /// @return gtId The id of Gearing Token

    function leverageByXt(
        address receiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) external returns (uint256 gtId);

    /// @notice Redeem underlying tokens after maturity
    /// @param ftAmount The amount of FT want to redeem
    function redeem(uint256 ftAmount) external;

    /// @notice Set the configuration of Gearing Token
    function updateGtConfig(bytes memory configData) external;
}
