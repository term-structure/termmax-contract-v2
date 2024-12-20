// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {ITermMaxTokenPair} from "./ITermMaxTokenPair.sol";
import {MarketConfig} from "./storage/TermMaxStorage.sol";

/**
 * @title TermMax Market interface
 * @author Term Structure Labs
 */
interface ITermMaxMarket {
    error TODO();
    error TOBEDEFINED();
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
    error CanNotRedeemBeforeFinalLiquidationDeadline(uint256 liquidationDeadline);
    /// @notice Error for evacuation mode is not actived
    error EvacuationIsNotActived();
    /// @notice Error for evacuation mode is actived
    error EvacuationIsActived();
    /// @notice Error for not enough excess FT/XT to withdraw
    error NotEnoughFtOrXtToWithdraw();

    /// @notice Emitted when market initialized
    /// @param tokenPair Underlying token
    /// @param openTime The unix time when the market starts trading
    /// @param maturity The unix time of maturity date
    event MarketInitialized(ITermMaxTokenPair indexed tokenPair, uint64 openTime, uint64 maturity);

    /// @notice Emitted when market config is updated
    event UpdateMarketConfig(MarketConfig config);
    /// @notice Emitted when change the value of lsf
    event UpdateLsf(uint32 lsf);
    /// @notice Emitted when setting the market whitelist
    event UpdateProvider(address provider);

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
    event RemoveLiquidity(address indexed caller, uint256 underlyingAmt, uint128 ftReserve, uint128 xtReserve);

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
    event Redeem(address indexed caller, uint128 proportion, uint128 underlyingAmt, uint128 feeAmt, bytes deliveryData);

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
    /// @param tokenPair The token pair of the market
    /// @param config_ Configuration of market
    /// @dev Only factory will call this function once when deploying new market
    function initialize(address admin, ITermMaxTokenPair tokenPair, MarketConfig memory config_) external;

    /// @notice Return the configuration
    function config() external view returns (MarketConfig memory);

    /// @notice Set the market configuration
    /// @param newConfig New configuration
    /// @param newFtReserve New FT reserve amount
    /// @param newXtReserve New XT reserve amount
    function updateMarketConfig(MarketConfig calldata newConfig, uint newFtReserve, uint newXtReserve) external;

    /// @notice Set the provider's whitelist
    function setProvider(address provider) external;

    /// @notice Return the reserves of FT and XT
    function ftXtReserves() external view returns (uint256 ftReserve, uint256 xtReserve);

    /// @notice Return the tokens in TermMax Market
    /// @return tokenPair Token Pair
    function tokenPair() external view returns (ITermMaxTokenPair tokenPair);

    /// @notice Return the tokens in TermMax Market
    /// @return ft Fixed-rate Token(bond token). Earning Fixed Income with High Certainty
    /// @return xt Intermediary Token for Collateralization and Leveragin
    /// @return gt Gearing Token
    /// @return collateral Collateral token
    /// @return underlying Underlying Token(debt)
    function tokens()
        external
        view
        returns (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateral, IERC20 underlying);

    /// @notice Return the apr of the market
    function apr() external view returns (uint apr_);

    /// @notice Buy FT using underlying token
    /// @param underlyingAmtIn The number of unterlying tokens input
    /// @param minTokenOut Minimum number of FT token outputs required
    /// @return netOut The actual number of FT tokens received
    function buyFt(uint128 underlyingAmtIn, uint128 minTokenOut) external returns (uint256 netOut);

    /// @notice Buy XT using underlying token
    /// @param underlyingAmtIn The number of unterlying tokens input
    /// @param minTokenOut Minimum number of XT token outputs required
    /// @return netOut The actual number of XT tokens received
    function buyXt(uint128 underlyingAmtIn, uint128 minTokenOut) external returns (uint256 netOut);

    /// @notice Sell FT to get underlying token
    /// @param ftAmtIn The number of FT tokens input
    /// @param minUnderlyingOut Minimum number of underlying token outputs required
    /// @return netOut The actual number of underlying tokens received
    function sellFt(uint128 ftAmtIn, uint128 minUnderlyingOut) external returns (uint256 netOut);

    /// @notice Sell XT to get underlying token
    /// @param xtAmtIn The number of XT tokens input
    /// @param minUnderlyingOut Minimum number of underlying token outputs required
    /// @return netOut The actual number of underlying tokens received
    function sellXt(uint128 xtAmtIn, uint128 minUnderlyingOut) external returns (uint256 netOut);

    /// @notice Suspension of market trading
    function pause() external;

    /// @notice Open Market Trading
    function unpause() external;
}
