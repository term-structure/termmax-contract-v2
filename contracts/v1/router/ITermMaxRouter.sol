// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {SwapUnit} from "./ISwapAdapter.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {ISwapCallback} from "../ISwapCallback.sol";

/**
 * @title TermMax Router interface
 * @author Term Structure Labs
 * @notice Interface for the main router contract that handles all user interactions with TermMax protocol
 * @dev This interface defines all external functions for swapping, leveraging, and managing positions
 */
interface ITermMaxRouter {
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
     * @notice Swaps an exact amount of input token for output token
     * @dev Uses specified orders for the swap path
     * @param tokenIn Input token to swap from
     * @param tokenOut Output token to swap to
     * @param recipient Address to receive the output tokens
     * @param orders Array of orders to use for the swap path
     * @param tradingAmts Array of amounts to trade for each order
     * @param minTokenOut Minimum amount of output tokens to receive
     * @param deadline The deadline timestamp for the transaction
     * @return netTokenOut Actual amount of output tokens received
     */
    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 minTokenOut,
        uint256 deadline
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Swaps tokens to receive an exact amount of output token
     * @dev Uses specified orders for the swap path
     * @param tokenIn Input token to swap from
     * @param tokenOut Output token to swap to
     * @param recipient Address to receive the output tokens
     * @param orders Array of orders to use for the swap path
     * @param tradingAmts Array of amounts to trade for each order
     * @param maxTokenIn Maximum amount of input tokens to spend
     * @param deadline The deadline timestamp for the transaction
     * @return netTokenIn Actual amount of input tokens spent
     */
    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 maxTokenIn,
        uint256 deadline
    ) external returns (uint256 netTokenIn);

    /**
     * @notice Sells FT and XT tokens for underlying tokens
     * @dev Executes multiple orders to sell tokens
     * @param recipient Address to receive the output tokens
     * @param market The market to sell tokens in
     * @param ftInAmt Amount of FT tokens to sell
     * @param xtInAmt Amount of XT tokens to sell
     * @param orders Array of orders to execute
     * @param amtsToSellTokens Array of amounts to sell for each order
     * @param minTokenOut Minimum amount of output tokens to receive
     * @param deadline The deadline timestamp for the transaction
     * @return netTokenOut Actual amount of output tokens received
     */
    function sellTokens(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        ITermMaxOrder[] memory orders,
        uint128[] memory amtsToSellTokens,
        uint128 minTokenOut,
        uint256 deadline
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Creates a leveraged position from input tokens
     * @dev Swaps tokens for XT and creates a leveraged position
     * @param recipient Address to receive the position
     * @param market The market to create position in
     * @param orders Array of orders to execute
     * @param amtsToBuyXt Array of amounts of XT to buy for each order
     * @param minXtOut Minimum amount of XT to establish the position
     * @param tokenToSwap Amount of tokens to swap
     * @param maxLtv Maximum loan-to-value ratio
     * @param units Array of swap units defining the swap path
     * @param deadline The deadline timestamp for the transaction
     * @return gtId ID of the generated GT token
     * @return netXtOut Amount of XT tokens received
     */
    function leverageFromToken(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder[] memory orders,
        uint128[] memory amtsToBuyXt,
        uint128 minXtOut,
        uint128 tokenToSwap,
        uint128 maxLtv,
        SwapUnit[] memory units,
        uint256 deadline
    ) external returns (uint256 gtId, uint256 netXtOut);

    /**
     * @notice Creates a leveraged position from XT tokens
     * @dev Uses existing XT tokens to create a leveraged position
     * @param recipient Address to receive the position
     * @param market The market to create position in
     * @param xtInAmt Amount of XT tokens to use
     * @param tokenInAmt Amount of additional tokens to use
     * @param maxLtv Maximum loan-to-value ratio
     * @param units Array of swap units defining the swap path
     * @return gtId ID of the generated GT token
     */
    function leverageFromXt(
        address recipient,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 tokenInAmt,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external returns (uint256 gtId);

    function leverageFromXtAndCollateral(
        address recipient,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 collateralInAmt,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external returns (uint256 gtId);

    /**
     * @notice Borrows tokens using collateral
     * @dev Creates a collateralized debt position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param collInAmt Amount of collateral to deposit
     * @param orders Array of orders to execute
     * @param tokenAmtsWantBuy Array of token amounts to buy
     * @param maxDebtAmt Maximum amount of debt to take on
     * @param deadline The deadline timestamp for the transaction
     * @return gtId ID of the generated GT token
     */
    function borrowTokenFromCollateral(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        ITermMaxOrder[] memory orders,
        uint128[] memory tokenAmtsWantBuy,
        uint128 maxDebtAmt,
        uint256 deadline
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
    function borrowTokenFromCollateral(address recipient, ITermMaxMarket market, uint256 collInAmt, uint256 borrowAmt)
        external
        returns (uint256 gtId);

    /**
     * @notice Borrows tokens from an existing GT position
     * @dev Increases the debt of an existing position
     * @param recipient Address to receive the borrowed tokens
     * @param market The market to borrow from
     * @param gtId ID of the GT token to borrow from
     * @param borrowAmt Amount of tokens to borrow
     */
    function borrowTokenFromGt(address recipient, ITermMaxMarket market, uint256 gtId, uint256 borrowAmt) external;

    /**
     * @notice Repays debt from collateral
     * @dev Repays debt and closes a position
     * @param recipient Address to receive any remaining collateral
     * @param market The market to repay debt in
     * @param gtId ID of the GT token to repay debt from
     * @param orders Array of orders to execute
     * @param amtsToBuyFt Array of amounts to buy for each order
     * @param byDebtToken Whether to repay debt using debt tokens
     * @param units Array of swap units defining the swap path
     * @param deadline The deadline timestamp for the transaction
     * @return netTokenOut Actual amount of tokens received
     */
    function flashRepayFromColl(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        ITermMaxOrder[] memory orders,
        uint128[] memory amtsToBuyFt,
        bool byDebtToken,
        SwapUnit[] memory units,
        uint256 deadline
    ) external returns (uint256 netTokenOut);

    /**
     * @notice Repays debt using FT tokens
     * @dev Repays debt and closes a position
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
     * @notice Creates an order and deposits tokens
     * @dev Creates a new order and deposits tokens to the market
     * @param market The market to create order in
     * @param maker Address of the order maker
     * @param maxXtReserve Maximum amount of XT to reserve
     * @param swapTrigger Swap trigger callback
     * @param debtTokenToDeposit Amount of debt tokens to deposit
     * @param ftToDeposit Amount of FT tokens to deposit
     * @param xtToDeposit Amount of XT tokens to deposit
     * @param curveCuts Curve cuts for the order
     * @return order The created order
     */
    function createOrderAndDeposit(
        ITermMaxMarket market,
        address maker,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        CurveCuts memory curveCuts
    ) external returns (ITermMaxOrder order);
}
