// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket, IGearingToken} from "../../v1/ITermMaxMarket.sol";
import {SwapUnit} from "../../v1/router/ISwapAdapter.sol";

/// @title TermMaxSwapPath
/// @notice Represents a path for swapping tokens in the TermMax protocol and third-party adapters
struct SwapPath {
    /// @notice The token input amount of the first unit in the path
    uint256 inputAmount;
    /// @notice The last unit will send the output token to this address
    address recipient;
    /// @notice If true, input amount will using balance onchain, otherwise using the input amount from sender
    bool useBalanceOnchain;
    /// @notice If uint's adapter is address(0), it means transfer the input token to recipient directly
    /// @notice If uint's adapter token in equals to token out, the unit will be skipped
    SwapUnit[] units;
}

enum FlashLoanType {
    COLLATERAL,
    DEBT
}

enum FlashRepayOptions {
    REPAY,
    ROLLOVER,
    ROLLOVER_AAVE,
    ROLLOVER_MORPHO
}

/**
 * @title TermMax RouterV2 interface
 * @author Term Structure Labs
 * @notice Interface for the main router contract that handles all user interactions with TermMax protocol
 * @dev This interface defines all external functions for swapping, leveraging, and managing positions
 */
interface ITermMaxRouterV2 {
    /**
     * @notice Swaps tokens using a predefined path
     * @dev Uses the SwapPath struct to define the swap path
     * @param paths Array of SwapPath structs defining the swap operations
     * @return netAmounts Array of amounts received for each swap operation
     */
    function swapTokens(SwapPath[] memory paths) external returns (uint256[] memory netAmounts);

    /**
     * @notice Leverages a position
     * @dev Creates a leveraged position in the specified market
     *      input/output: =>, swap: ->
     *      path0 (=> xt or => token -> xt) => router
     *      case1 by debt token: path1 (=> debt token or => token -> debt token) => router
     *      case2 by collateral token: path1 (=> collateral token or => token -> collateral token) => router
     *      swapCollateralPath debt token -> collateral token => router
     * @param recipient Address to receive the leveraged position
     * @param market The market to leverage in
     * @param maxLtv Maximum loan-to-value ratio for the leverage
     * @param isV1 Indicates if the leverage is for market V1 or V2
     * @param inputPaths Array of SwapPath structs defining the input token paths
     * @param swapCollateralPath SwapPath for collateral token
     * @return gtId ID of the generated GT token
     * @return netXtOut Actual amount of XT tokens input after swapping
     */
    function leverage(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
        bool isV1,
        SwapPath[] memory inputPaths,
        SwapPath memory swapCollateralPath
    ) external returns (uint256 gtId, uint256 netXtOut);

    /**
     * @notice Borrows tokens using collateral
     * @dev Creates a collateralized debt position
     *      input/output: =>, swap: ->
     *      swapFtPath ft -> debt token => recipient
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param collInAmt Amount of collateral
     * @param maxDebtAmt Maximum amount of debt to incur
     * @param swapFtPath SwapPath for swapping FT token to debt token
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateral(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint128 maxDebtAmt,
        SwapPath memory swapFtPath
    ) external returns (uint256 gtId);

    /**
     * @notice Borrows tokens using collateral and XT
     * @dev Creates a collateralized debt position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param collInAmt Amount of collateral to deposit
     * @param borrowAmt Amount of tokens to borrow
     * @param isV1 Indicates if the borrow is for market V1 or V2
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateralAndXt(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt,
        bool isV1
    ) external returns (uint256 gtId);

    /**
     * @notice Repays debt from collateral
     * @dev Repays debt and closes a position
     *      input/output: =>, swap: ->
     *      swapPath: collateral -> debt token (-> exact ft token. optional) => router
     * @param recipient Address to receive any remaining collateral
     * @param market The market to repay debt in
     * @param gtId ID of the GT token to repay debt from
     * @param byDebtToken True if repaying with debt token, false if using FT token
     * @param expectedOutput The expect debt token ouput amount after flashrepay
     * @param callbackData The data for callback, abi.encode(FlashRepayOptions.FLASH_REPAY, abi.encode(swapPath))
     * @return netTokenOut Actual amount of tokens received
     */
    function flashRepayFromCollForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        uint256 expectedOutput,
        bytes memory callbackData
    ) external returns (uint256 netTokenOut);

    function flashRepayFromCollForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        bool byDebtToken,
        uint256 expectedOutput,
        uint256 removedCollateral,
        bytes memory callbackData
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Rollover GT position
     * @dev This function allows users to rollover their GT position to a new market or third-protocol
     * @param gtToken The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param additionalAsset The additional asset(debt token, old collateral token, new collateral token) to reduce the LTV
     * @param additionalAmt Amount of the additional asset
     * @param rolloverData Additional data for the rollover operation
     * rollover to TermMax: abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(recipient, nextMarket, maxLtv, collateralPath, debtTokenPath))
     *  - collateralPaths: old collateral -> new collateral => router
     *  - debtTokenPaths: ft -> debt token => router
     * rollover to Aave: abi.encode(FlashRepayOptions.ROLLOVER_AAVE, abi.encode(recipient, oldCollateral, aave, interestRateMode, referralCode, collateralPath))
     * rollover to Morpho: abi.encode(FlashRepayOptions.ROLLOVER_MORPHO, abi.encode(recipient, oldCollateral, morpho, marketId, collateralPath))
     * @return newGtId The ID of the newly created GT token in the next market, newGtId is zero if rollover to Aave or Morpho
     */
    function rolloverGtForV1(
        IGearingToken gtToken,
        uint256 gtId,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) external returns (uint256 newGtId);

    /**
     * @notice Rollover GT position
     * @dev This function allows users to rollover their GT position to a new market or third-protocol
     * @param gtToken The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param repayAmt Amount of debt to repay the old GT position
     * @param removedCollateral Amount of collateral to remove from the old position
     * @param additionalAsset The additional asset(debt or new collateral token) to reduce the LTV
     * @param additionalAmt Amount of the additional asset
     * @param rolloverData Additional data for the rollover operation
     * rollover to TermMax: abi.encode(FlashRepayOptions.ROLLOVER, abi.encode(recipient, nextMarket, maxLtv, collateralPath, debtTokenPath))
     *  - collateralPaths: old collateral -> new collateral => router
     *  - debtTokenPaths: ft -> debt token => router
     * rollover to Aave: abi.encode(FlashRepayOptions.ROLLOVER_AAVE, abi.encode(recipient, aave, interestRateMode, referralCode, collateralPath))
     * rollover to Morpho: abi.encode(FlashRepayOptions.ROLLOVER_MORPHO, abi.encode(recipient, morpho, marketId, collateralPath))
     * @return newGtId The ID of the newly created GT token in the next market, newGtId is zero if rollover to Aave or Morpho
     */
    function rolloverGtForV2(
        IGearingToken gtToken,
        uint256 gtId,
        uint256 repayAmt,
        uint256 removedCollateral,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) external returns (uint256 newGtId);

    /**
     * @notice Swaps tokens and repays debt in a GearingToken position
     * @dev This function allows users to swap tokens and repay debt in a GearingToken position
     * @dev input/output: =>, swap: ->
     *      path 0: => any token -> debt token/ft token => router
     *      path 1(optional): remaining debt token => recipient
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GearingToken position to repay
     * @param repayAmt The amount to repay
     * @param byDebtToken Indicates if the repayment is by debt token
     * @param paths The SwapPath struct defining the swap operations
     * @return netOutOrIns The net amounts of tokens received or cost when swapping
     */
    function swapAndRepay(IGearingToken gt, uint256 gtId, uint128 repayAmt, bool byDebtToken, SwapPath[] memory paths)
        external
        returns (uint256[] memory netOutOrIns);
}
