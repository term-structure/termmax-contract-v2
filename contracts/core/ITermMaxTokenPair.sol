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
    /// @notice Error for lsf value equals 0 or bigger than 1e8
    error InvalidLsf(uint32 lsf);
    /// @notice Error for the collateral and underlying are the same token
    error CollateralCanNotEqualUnderlyinng();
    /// @notice Error for repeat initialization of market
    error MarketHasBeenInitialized();
    /// @notice Error for it is not the opening trading day yet
    error MarketIsNotOpen();
    /// @notice Error for the maturity day has been reached
    error MarketWasClosed();
    /// @notice Error for provider not whitelisted
    error ProviderNotWhitelisted(address provider);
    /// @notice Error for receiving zero lp token when providing liquidity
    error LpOutputAmtIsZero(uint256 underlyingAmt);
    /// @notice Error for lsf is changed between user post trade request
    error LsfChanged();
    /// @notice Error for apr is less than min apr
    error AprLessThanMinApr(int64 apr, int64 minApr);
    /// @notice Error for the actual output value does not match the expected value
    error UnexpectedAmount(uint128 expectedAmt, uint128 actualAmt);
    /// @notice Error for redeeming before the liquidation window
    error CanNotRedeemBeforeFinalLiquidationDeadline(
        uint256 liquidationDeadline
    );
    /// @notice Error for evacuation mode is not actived
    error EvacuationIsNotActived();
    /// @notice Error for evacuation mode is actived
    error EvacuationIsActived();
    /// @notice Error for not enough excess FT/XT to withdraw
    error NotEnoughFtOrXtToWithdraw();

    /// @notice Emitted when market initialized
    /// @param collateral Collateral token
    /// @param underlying Underlying token
    /// @param openTime The unix time when the market starts trading
    /// @param maturity The unix time of maturity date
    /// @param tokens TermMax Market tokens, sort by [FT, XT, LpFT, LpXt]
    /// @param gt Gearing token
    event MarketInitialized(
        address indexed collateral,
        IERC20 indexed underlying,
        uint64 openTime,
        uint64 maturity,
        IMintableERC20[4] tokens,
        IGearingToken gt
    );

    /// @notice Emitted when market config is updated
    event UpdateTokenPairConfig(TokenPairConfig config);
    /// @notice Emitted when change the value of lsf
    event UpdateLsf(uint32 lsf);
    /// @notice Emitted when setting the market whitelist
    event UpdateProviderWhitelist(address provider, bool isWhiteList);

    /// @notice Emitted when providing liquidity to market
    /// @param caller Who call the function
    /// @param underlyingAmt Amount of underlying token provided
    /// @param lpFtAmt  The number of LpFT tokens received
    /// @param lpXtAmt The number of LpXT tokens received
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event ProvideLiquidity(
        address indexed caller,
        uint256 underlyingAmt,
        uint128 lpFtAmt,
        uint128 lpXtAmt,
        uint128 ftReserve,
        uint128 xtReserve
    );

    /// @notice Emitted when withdrawing FT/XT from market
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
    /// @param token  The token want to buy
    /// @param underlyingAmt The amount of underlying tokens traded
    /// @param expectedAmt Expected number of tokens to be obtained
    /// @param actualAmt The number of FT/XT tokens received
    /// @param feeAmt Transaction Fees
    /// @param newApr New apr value with BASE_DECIMALS after do this action
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event BuyToken(
        address indexed caller,
        IMintableERC20 indexed token,
        uint128 underlyingAmt,
        uint128 expectedAmt,
        uint128 actualAmt,
        uint128 feeAmt,
        int64 newApr,
        uint128 ftReserve,
        uint128 xtReserve
    );

    /// @notice Emitted when sell FT/XT
    /// @param caller Who call the function
    /// @param token  The token want to sell
    /// @param tokenAmt The amount of token traded
    /// @param expectedAmt Expected number of underlying tokens to be obtained
    /// @param actualAmt The number of underluing tokens received
    /// @param feeAmt Transaction Fees
    /// @param newApr New apr value with BASE_DECIMALS after do this action
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event SellToken(
        address indexed caller,
        IMintableERC20 indexed token,
        uint128 tokenAmt,
        uint128 expectedAmt,
        uint128 actualAmt,
        uint128 feeAmt,
        int64 newApr,
        uint128 ftReserve,
        uint128 xtReserve
    );

    /// @notice Emitted when removing liquidity from market
    /// @param caller Who call the function
    /// @param underlyingAmt the amount of underlying removed
    /// @param ftReserve The new FT reserve amount
    /// @param xtReserve The new XT reserve amount
    event RemoveLiquidity(
        address indexed caller,
        uint256 underlyingAmt,
        uint128 ftReserve,
        uint128 xtReserve
    );

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

    /// @notice Emitted when evacuating liquidity
    /// @param caller Who call the function
    /// @param lpFtAmt  The number of LpFT tokens burned
    /// @param lpXtAmt The number of LpXT tokens burned
    /// @param ftAmt The number of XT tokens received
    /// @param xtAmt The number of XT tokens received
    /// @param underlyingAmt The amount of underlying received
    event Evacuate(
        address indexed caller,
        uint128 lpFtAmt,
        uint128 lpXtAmt,
        uint128 ftAmt,
        uint128 xtAmt,
        uint256 underlyingAmt
    );
    /// @notice Emitted when withdrawing the excess FT and XT
    /// @param to Who receive the excess FT and XT
    /// @param ftAmt The number of FT tokens received
    /// @param xtAmt The number of XT tokens received
    event WithdrawExcessFtXt(address indexed to, uint128 ftAmt, uint128 xtAmt);

    /// @notice Initialize the token and configuration of the market
    /// @param admin Administrator address for configuring parameters such as transaction fees
    /// @param collateral_ Collateral token
    /// @param underlying_ Underlying Token(debt)
    /// @param tokens_ TermMax Market tokens, sort by [FT, XT, LpFT, LpXt]
    /// @param gt_ TermMax Gearing Token
    /// @param config_ Configuration of market
    /// @dev Only factory will call this function once when deploying new market
    function initialize(
        address admin,
        address collateral_,
        IERC20 underlying_,
        IMintableERC20[4] memory tokens_,
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

    /// @notice Sell ​​FT and XT in equal proportion to initial LTV for underlying token.
    ///         No price slippage or handling fees.
    /// @param underlyingAmt Amount of underlying token want to obtain
    function redeemFtAndXtToUnderlying(uint256 underlyingAmt) external;

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
