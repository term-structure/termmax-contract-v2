// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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
     * @dev input/output: =>, swap: ->
     *      path0: => xt/ft -> debt token => router/recipient
     *      path1(optional): debt token -> unwrap => recipient
     * @param recipient Address to receive the output tokens
     * @param market The market to burn FT and XT tokens
     * @param ftInAmt Amount of FT tokens to swap
     * @param xtInAmt Amount of XT tokens to swap
     * @param swapPaths Array of SwapPath structs defining the swap paths
     * @return netTokenOut Actual amount of tokens received after the swap
     */
    function sellFtAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        SwapPath[] memory swapPaths
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Swaps ft and xt tokens for a specific marketV2
     * @dev This function allows users to swap FT and XT tokens for a specific market
     * @dev input/output: =>, swap: ->
     *      path0: => xt/ft -> debt token => router/recipient
     *      path1(optional): debt token -> unwrap => recipient
     * @param recipient Address to receive the output tokens
     * @param market The market to burn FT and XT tokens
     * @param ftInAmt Amount of FT tokens to swap
     * @param xtInAmt Amount of XT tokens to swap
     * @param swapPaths Array of SwapPath structs defining the swap paths
     * @return netTokenOut Actual amount of tokens received after the swap
     */
    function sellFtAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        SwapPath[] memory swapPaths
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
     * @param pathsAfterBorrow Array of SwapPath structs defining the swap paths after borrowing
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateralAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt,
        SwapPath[] memory pathsAfterBorrow
    ) external returns (uint256 gtId);

    /**
     * @notice Borrows tokens using collateral and XT
     * @dev Creates a collateralized debt position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param collInAmt Amount of collateral to deposit
     * @param borrowAmt Amount of tokens to borrow
     * @param pathsAfterBorrow Array of SwapPath structs defining the swap paths after borrowing
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateralAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt,
        SwapPath[] memory pathsAfterBorrow
    ) external returns (uint256 gtId);

    /**
     * @notice Borrows tokens from an existing GT position and XT
     * @dev Increases the debt of an existing position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param gtId ID of the GT token to borrow from
     * @param borrowAmt Amount of tokens to borrow
     * @param pathsAfterBorrow Array of SwapPath structs defining the swap paths after borrowing
     */
    function borrowTokenFromGtAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 borrowAmt,
        SwapPath[] memory pathsAfterBorrow
    ) external;

    /**
     * @notice Borrows tokens from an existing GT position and XT
     * @dev Increases the debt of an existing position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param gtId ID of the GT token to borrow from
     * @param borrowAmt Amount of tokens to borrow
     */
    function borrowTokenFromGtAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 borrowAmt,
        SwapPath[] memory pathsAfterBorrow
    ) external;

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
     *      path0: => debt token -> exact ft token => router
     *      path1: remaining debt token => recipient
     * @param recipient Address to receive any remaining tokens
     * @param market The market to repay debt in
     * @param gtId ID of the GT token to repay debt from
     * @param paths Array of SwapPath structs defining the swap paths
     * @return netCost Actual amount of tokens spent to buy FT tokens
     */
    function repayByTokenThroughFt(address recipient, ITermMaxMarket market, uint256 gtId, SwapPath[] memory paths)
        external
        returns (uint256 netCost);

    /**
     * @notice Rollover GT position to a new market with additional assets(dont support partial rollover)
     * @dev This function allows users to rollover their GT position to a new market
     *      input/output: =>, swap: ->
     *      collateralPaths: old collateral -> new collateral => router
     *      debtTokenPaths: ft -> debt token => router
     * @param recipient The address that will receive the new GT token
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param nextMarket The next market to rollover into
     * @param maxLtv Maximum loan-to-value ratio for the next position
     * @param additionalCollateral Amount of collateral to add to the new position
     * @param additionalDebt Amount of debt to add to the new position
     * @param collateralPath SwapPath to swap old collateral to new collateral
     * @param debtTokenPath SwapPath to swap ft to exact debt token
     * @return newGtId The ID of the newly created GT token in the next market
     */
    function rolloverGtForV1(
        address recipient,
        IGearingToken gt,
        uint256 gtId,
        ITermMaxMarket nextMarket,
        uint128 maxLtv,
        uint256 additionalCollateral,
        uint256 additionalDebt,
        SwapPath memory collateralPath,
        SwapPath memory debtTokenPath
    ) external returns (uint256 newGtId);

    /**
     * @notice Rollover GT position to a new market with additional assets(dont support partial rollover)
     * @dev This function allows users to rollover their GT position to a new market
     *      input/output: =>, swap: ->
     *      collateralPaths: old collateral -> new collateral => router
     *      debtTokenPaths: ft -> debt token => router
     * @param recipient The address that will receive the new GT token
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GT token being rolled over
     * @param nextMarket The next market to rollover into
     * @param maxLtv Maximum loan-to-value ratio for the next position
     * @param repayAmt Amount of debt to repay the old GT position
     * @param removedCollateral Amount of collateral to remove from the old position
     * @param additionalCollateral Amount of collateral to add to the new position
     * @param additionalDebt Amount of debt to add to the new position
     * @param collateralPath SwapPath to swap old collateral to new collateral
     * @param debtTokenPath SwapPath to swap ft to exact debt token
     * @return newGtId The ID of the newly created GT token in the next market
     */
    function rolloverGtForV2(
        address recipient,
        IGearingToken gt,
        uint256 gtId,
        ITermMaxMarket nextMarket,
        uint128 maxLtv,
        uint128 repayAmt,
        uint256 removedCollateral,
        uint256 additionalCollateral,
        uint256 additionalDebt,
        SwapPath memory collateralPath,
        SwapPath memory debtTokenPath
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

    /**
     * @notice Swaps tokens and mints ft and xt tokens in the TermMax protocol
     * @dev This function allows users to swap tokens and mint ft and xt tokens in the TermMax protocol
     * @dev input/output: =>, swap: ->
     *      path 0: => any token -> debt token => router
     * @param market The market to mint the tokens in
     * @param paths The SwapPath struct defining the swap operations
     * @return netOut The net amount of ft and xt tokens received after the swap
     */
    function SwapAndMint(address recipient, ITermMaxMarket market, SwapPath[] memory paths)
        external
        returns (uint256 netOut);

    /**
     * @notice Redeems FT tokens from a market and swaps output tokens
     * @dev This function allows users to redeem FT tokens from a market and swap output tokens
     * @dev input/output: =>, swap: ->
     *      path0: => debt token -> output token => recipient
     *      path1(optional): collateral token -> output token => recipient
     * @param recipient Address to receive the output tokens
     * @param market The market to redeem from
     * @param ftAmt Amount of FT tokens to redeem
     * @param paths Array of SwapPath structs defining the swap paths
     * @return netOut The net amount of tokens received after the swap
     */
    function RedeemFromMarketAndSwap(address recipient, ITermMaxMarket market, uint256 ftAmt, SwapPath[] memory paths)
        external
        returns (uint256 netOut);
    /**
     * @notice Swaps tokens and repays debt in a GearingToken position
     * @dev This function allows users to swap tokens and repay debt in a GearingToken position
     * @dev input/output: =>, swap: ->
     *      path 0: => any token -> debt token/ft token => router
     * @param gt The GearingToken contract instance
     * @param gtId The ID of the GearingToken position to repay
     * @param paths The SwapPath struct defining the swap operations
     * @return netOut The net amount of tokens received after the swap
     */
    function SwapAndRepay(IGearingToken gt, uint256 gtId, SwapPath[] memory paths) external returns (uint256 netOut);

    /**
     * @notice Swaps tokens and deposits into a vault
     * @dev This function allows users to swap tokens and deposit into an IERC4626 vault
     * @dev input/output: =>, swap: ->
     *      path0: => any token -> vault underlying => router
     * @param recipient Address to receive the share tokens
     * @param vault The IERC4626 vault to deposit into
     * @param paths The SwapPath struct defining the swap operations
     * @return netOut The net amount of share tokens received after swapping and depositing
     */
    function SwapAndDeposit(address recipient, IERC4626 vault, SwapPath[] memory paths)
        external
        returns (uint256 netOut);
    /**
     * @notice Redeems shares from a vault and swaps the output tokens
     * @dev This function allows users to redeem shares from an IERC4626 vault and swap the output tokens
     * @dev input/output: =>, swap: ->
     *      swapPath: vault underlying -> output token => recipient
     * @param recipient Address to receive the output tokens
     * @param vault The IERC4626 vault to redeem shares from
     * @param shareAmt Amount of shares to redeem from the vault
     * @param swapPath The SwapPath struct defining the swap operations
     * @return netOut The net amount of tokens received after redeeming and swapping
     */
    function RedeemFromVaultAndSwap(address recipient, IERC4626 vault, uint256 shareAmt, SwapPath memory swapPath)
        external
        returns (uint256 netOut);
}
