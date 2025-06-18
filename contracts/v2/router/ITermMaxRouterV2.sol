// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket, IGearingToken} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "../../v1/ITermMaxOrder.sol";
import {SwapUnit} from "../../v1/router/ISwapAdapter.sol";
import {ISwapCallback} from "../../v1/ISwapCallback.sol";
import {OrderConfig} from "../../v1/storage/TermMaxStorage.sol";

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
     * @notice Pauses all protocol operations
     * @dev Can only be called by authorized addresses
     */
    function pause() external;

    /**
     * @notice Unpauses protocol operations
     * @dev Can only be called by authorized addresses
     */
    function unpause() external;

    /**
     * @notice View the adapter whitelist status
     * @dev Used for controlling which swap adapters can be used
     * @param adapter The adapter's address to check whitelist status for
     * @return True if whitelisted, false otherwise
     */
    function adapterWhitelist(address adapter) external view returns (bool);

    /**
     * @notice Set the adapter whitelist status
     * @dev Used for controlling which swap adapters can be used
     * @param adapter The adapter's address to set whitelist status for
     * @param isWhitelist True to whitelist, false to remove from whitelist
     */
    function setAdapterWhitelist(address adapter, bool isWhitelist) external;

    /**
     * @notice Retrieves all assets owned by an address in a specific market
     * @dev Returns both ERC20 tokens and GT (Governance Token) positions
     * @param market The market to query assets from
     * @param owner The address to check assets for
     * @return tokens Array of ERC20 token addresses
     * @return balances Corresponding balances for each token
     * @return gt The GT token contract address
     * @return gtIds Array of GT token IDs owned by the address
     */
    function assetsWithERC20Collateral(ITermMaxMarket market, address owner)
        external
        view
        returns (IERC20[4] memory tokens, uint256[4] memory balances, address gt, uint256[] memory gtIds);

    /**
     * @notice Swaps tokens using a predefined path
     * @dev Uses the SwapPath struct to define the swap path
     * @param paths Array of SwapPath structs defining the swap operations
     * @return netAmounts Array of amounts received for each swap operation
     */
    function swapTokens(SwapPath[] memory paths) external returns (uint256[] memory netAmounts);

    /**
     * @notice Swaps ft and xt tokens for a specific marketV1
     * @dev This function allows users to swap FT and XT tokens for a specific market
     * @param recipient Address to receive the output tokens
     * @param market The market to burn FT and XT tokens
     * @param ftInAmt Amount of FT tokens to swap
     * @param xtInAmt Amount of XT tokens to swap
     * @param path SwapPath to swap xt or ft token
     * @return netTokenOut Actual amount of tokens received after the swap
     */
    function sellFtAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        SwapPath memory path
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Swaps ft and xt tokens for a specific marketV2
     * @dev This function allows users to swap FT and XT tokens for a specific market
     * @param recipient Address to receive the output tokens
     * @param market The market to burn FT and XT tokens
     * @param ftInAmt Amount of FT tokens to swap
     * @param xtInAmt Amount of XT tokens to swap
     * @param path SwapPath to swap xt or ft token
     * @return netTokenOut Actual amount of tokens received after the swap
     */
    function sellFtAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        SwapPath memory path
    ) external returns (uint256 netTokenOut);

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
     * @param inputPaths Array of SwapPath structs defining the input token paths
     * @param swapCollateralPath SwapPath for collateral token
     * @return gtId ID of the generated GT token
     * @return netXtOut Actual amount of XT tokens input after swapping
     */
    function leverageForV1(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
        SwapPath[] memory inputPaths,
        SwapPath memory swapCollateralPath
    ) external returns (uint256 gtId, uint256 netXtOut);

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
     * @param inputPaths Array of SwapPath structs defining the input token paths
     * @param swapCollateralPath SwapPath for collateral token
     * @return gtId ID of the generated GT token
     * @return netXtOut Actual amount of XT tokens input after swapping
     */
    function leverageForV2(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
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
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateralAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt
    ) external returns (uint256 gtId);

    /**
     * @notice Borrows tokens using collateral and XT
     * @dev Creates a collateralized debt position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param collInAmt Amount of collateral to deposit
     * @param borrowAmt Amount of tokens to borrow
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateralAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt
    ) external returns (uint256 gtId);

    /**
     * @notice Borrows tokens from an existing GT position and XT
     * @dev Increases the debt of an existing position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param gtId ID of the GT token to borrow from
     * @param borrowAmt Amount of tokens to borrow
     */
    function borrowTokenFromGtAndXtForV1(address recipient, ITermMaxMarket market, uint256 gtId, uint256 borrowAmt)
        external;

    /**
     * @notice Borrows tokens from an existing GT position and XT
     * @dev Increases the debt of an existing position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param gtId ID of the GT token to borrow from
     * @param borrowAmt Amount of tokens to borrow
     */
    function borrowTokenFromGtAndXtForV2(address recipient, ITermMaxMarket market, uint256 gtId, uint256 borrowAmt)
        external;

    /**
     * @notice Repays debt from collateral
     * @dev Repays debt and closes a position
     *      input/output: =>, swap: ->
     *      path0: collateral -> debt token (-> exact ft token. optional) => router
     * @param recipient Address to receive any remaining collateral
     * @param market The market to repay debt in
     * @param gtId ID of the GT token to repay debt from
     * @param byDebtToken True if repaying with debt token, false if using FT token
     * @param swapPaths Array of SwapPath structs defining the swap paths
     * @return netTokenOut Actual amount of tokens received
     */
    function flashRepayFromCollForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        SwapPath[] memory swapPaths
    ) external returns (uint256 netTokenOut);

    function flashRepayFromCollForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        bool byDebtToken,
        bytes memory removedCollateral,
        SwapPath[] memory swapPaths
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Repays debt using FT tokens
     * @dev Repays debt and closes a position
     * @dev If collateral value is larger than debt, please swap collateral partially and add a swap path to defend MEV attack
     *      input/output: =>, swap: ->
     *      path0: collateral -> debt token (-> exact ft token. optional) => router
     * @param recipient Address to receive any remaining tokens
     * @param market The market to repay debt in
     * @param gtId ID of the GT token to repay debt from
     * @param orders Array of orders to execute
     * @param ftAmtsWantBuy Array of FT amounts to buy for each order
     * @param maxTokenIn Maximum amount of tokens to spend
     * @param deadline The deadline timestamp for the transaction
     * @return returnAmt Actual amount of tokens returned
     */
    function repayByTokenThroughFt(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        ITermMaxOrder[] memory orders,
        uint128[] memory ftAmtsWantBuy,
        uint128 maxTokenIn,
        uint256 deadline
    ) external returns (uint256 returnAmt);

    /**
     * @notice Redeems FT tokens and swaps for underlying tokens
     * @dev Executes a swap to redeem FT tokens
     * @param recipient Address to receive the output tokens
     * @param market The market to redeem FT tokens in
     * @param ftAmount Amount of FT tokens to redeem
     * @param units Array of swap units defining the swap path
     * @param minTokenOut Minimum amount of output tokens to receive
     * @return redeemedAmt Actual amount of output tokens received
     */
    function redeemAndSwap(
        address recipient,
        ITermMaxMarket market,
        uint256 ftAmount,
        SwapUnit[] memory units,
        uint256 minTokenOut
    ) external returns (uint256 redeemedAmt);

    /**
     * @notice Rollover GT position to a new market with additional assets(dont support partial rollover)
     * @dev This function allows users to rollover their GT position to a new market
     * @param recipient The address that will receive the new GT token
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param additionalAssets Amount of additional assets to add to the position
     * @param units Array of swap units defining the external swap path
     * @param nextMarket The next market to rollover into
     * @param additionnalNextCollateral Additional collateral for the next market
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
        uint256 additionnalNextCollateral,
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
     * @param additionnalNextCollateral Additional collateral for the next market
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
        uint256 additionnalNextCollateral,
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
