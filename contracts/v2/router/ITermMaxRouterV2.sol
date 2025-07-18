// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket, IGearingToken} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "../../v1/ITermMaxOrder.sol";
import {SwapUnit} from "../../v1/router/ISwapAdapter.sol";
import {ISwapCallback} from "../../v1/ISwapCallback.sol";
import {OrderConfig} from "../../v1/storage/TermMaxStorage.sol";

/**
 * @title TermMax RouterV2 interface
 * @author Term Structure Labs
 * @notice Interface for the main router contract that handles all user interactions with TermMax protocol
 * @dev This interface defines all external functions for swapping, leveraging, and managing positions
 */
interface ITermMaxRouterV2 {
    struct TermMaxSwapData {
        address tokenIn;
        address tokenOut;
        ITermMaxOrder[] orders;
        uint128[] tradingAmts;
        uint128 netTokenAmt;
        uint256 deadline;
    }

    /**
     * @notice Repays debt from collateral
     * @dev Repays debt and closes a position
     * @param recipient Address to receive any remaining collateral
     * @param market The market to repay debt in
     * @param gtId ID of the GT token to repay debt from
     * @param byDebtToken True if repaying with debt token, false if using FT token
     * @param expectedOutput Expected amount of tokens to receive after swap
     * @param units Array of swap units defining the external swap path
     * @param swapData Data for the termmax swap operation
     * @return netTokenOut Actual amount of tokens received
     */
    function flashRepayFromColl(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        uint256 expectedOutput,
        SwapUnit[] memory units,
        TermMaxSwapData memory swapData
    ) external returns (uint256 netTokenOut);

    function flashRepayFromCollV2(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        bool byDebtToken,
        uint256 expectedOutput,
        bytes memory removedCollateral,
        SwapUnit[] memory units,
        TermMaxSwapData memory swapData
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Repays debt
     * @param market The TermMax market to repay in
     * @param gtId The ID of the GT to repay
     * @param maxRepayAmt Maximum amount of tokens to repay
     * @param byDebtToken Whether to repay using debt tokens
     * @return repayAmt The actual amount repaid
     */
    function repayGt(ITermMaxMarket market, uint256 gtId, uint128 maxRepayAmt, bool byDebtToken)
        external
        returns (uint128 repayAmt);

    /**
     * @notice Rollover GT position to a new market with additional assets(dont support partial rollover)
     * @dev This function allows users to rollover their GT position to a new market
     * @param recipient The address that will receive the new GT token
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param additionalAssets Amount of additional assets to add to the position
     * @param units Array of swap units defining the external swap path
     * @param nextMarket The next market to rollover into
     * @param additionalNextCollateral Additional collateral for the next market
     * @param swapData Data for the termmax swap operation
     * @param maxLtv Maximum loan-to-value ratio for the rollover
     * @return newGtId The ID of the newly created GT token in the next market
     */
    function rolloverGt(
        address recipient,
        IGearingToken gt,
        uint256 gtId,
        uint128 additionalAssets,
        SwapUnit[] memory units,
        ITermMaxMarket nextMarket,
        uint256 additionalNextCollateral,
        TermMaxSwapData memory swapData,
        uint128 maxLtv
    ) external returns (uint256 newGtId);

    /**
     * @notice Rollover GT position to a new market with additional assets(allow partial rollover)
     * @dev This function allows users to rollover their GT position to a new market
     * @param recipient The address that will receive the new GT token
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param repayAmt Amount of debt to repay
     * @param additionalAssets Amount of additional assets to add to the position
     * @param removedCollateral Amount of collateral to remove from the position
     * @param units Array of swap units defining the external swap path
     * @param nextMarket The next market to rollover into
     * @param additionalNextCollateral Additional collateral for the next market
     * @param swapData Data for the termmax swap operation
     * @param maxLtv Maximum loan-to-value ratio for the rollover
     * @return newGtId The ID of the newly created GT token in the next market
     */
    function rolloverGtV2(
        address recipient,
        IGearingToken gt,
        uint256 gtId,
        uint128 repayAmt,
        uint128 additionalAssets,
        uint256 removedCollateral,
        SwapUnit[] memory units,
        ITermMaxMarket nextMarket,
        uint256 additionalNextCollateral,
        TermMaxSwapData memory swapData,
        uint128 maxLtv
    ) external returns (uint256 newGtId);

    /**
     * @notice Places an order and mints a GT token(The gt token will not be linked to the order)
     * @dev This function is used to create a new order in the TermMax protocol
     * @param market The market to place the order in
     * @param maker The address of the maker placing the order
     * @param collateralToMintGt Amount of collateral to mint GT tokens
     * @param debtTokenToDeposit Amount of debt tokens to deposit
     * @param ftToDeposit Amount of FT tokens to deposit
     * @param xtToDeposit Amount of XT tokens to deposit
     * @param orderConfig Configuration parameters for the order
     * @return order The created ITermMaxOrder instance
     * @return gtId The ID of the minted GT token
     */
    function placeOrderForV1(
        ITermMaxMarket market,
        address maker,
        uint256 collateralToMintGt,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        OrderConfig memory orderConfig
    ) external returns (ITermMaxOrder order, uint256 gtId);

    /**
     * @notice Places an order and mints a GT token(the gt token will be linked to the order)
     * @dev This function is used to create a new order in the TermMax protocol
     * @param market The market to place the order in
     * @param maker The address of the maker placing the order
     * @param collateralToMintGt Amount of collateral to mint GT tokens
     * @param debtTokenToDeposit Amount of debt tokens to deposit
     * @param ftToDeposit Amount of FT tokens to deposit
     * @param xtToDeposit Amount of XT tokens to deposit
     * @param orderConfig Configuration parameters for the order
     * @return order The created ITermMaxOrder instance
     * @return gtId The ID of the minted GT token
     */
    function placeOrderForV2(
        ITermMaxMarket market,
        address maker,
        uint256 collateralToMintGt,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        OrderConfig memory orderConfig
    ) external returns (ITermMaxOrder order, uint256 gtId);
}
