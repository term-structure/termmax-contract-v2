// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";

/**
 * @title Router Events Interface
 * @notice Events emitted by the TermMax router operations
 */
interface RouterEvents {
    /**
     * @notice Emitted when a market's whitelist status is updated
     * @param market The address of the market
     * param isWhitelist Whether the market is whitelisted
     */
    event UpdateMarketWhiteList(address market, bool isWhitelist);

    /**
     * @notice Emitted when a swap adapter's whitelist status is updated
     * @param adapter The address of the swap adapter
     * @param isWhitelist Whether the adapter is whitelisted
     */
    event UpdateSwapAdapterWhiteList(address adapter, bool isWhitelist);

    /**
     * @notice Emitted when tokens are swapped for exact tokens
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param caller The address initiating the swap
     * @param recipient The address receiving the output tokens
     * @param orders The array of orders used in the swap
     * @param tradingAmts The array of trading amounts
     * @param actualTokenOut The actual amount of output tokens
     */
    event SwapExactTokenToToken(
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        address caller,
        address recipient,
        ITermMaxOrder[] orders,
        uint128[] tradingAmts,
        uint256 actualTokenOut
    );

    /**
     * @notice Emitted when tokens are swapped for exact tokens
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param caller The address initiating the swap
     * @param recipient The address receiving the output tokens
     * @param orders The array of orders used in the swap
     * @param tradingAmts The array of trading amounts
     * @param actualTokenIn The actual amount of input tokens
     */
    event SwapTokenToExactToken(
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        address caller,
        address recipient,
        ITermMaxOrder[] orders,
        uint128[] tradingAmts,
        uint256 actualTokenIn
    );

    /**
     * @notice Emitted when tokens are sold
     * @param market The address of the market
     * @param caller The address initiating the sale
     * @param recipient The address receiving the output tokens
     * @param ftInAmt The amount of ft tokens sold
     * @param xtInAmt The amount of xt tokens sold
     * @param orders The array of orders used in the sale
     * @param amtsToSellTokens The array of amounts to sell tokens
     * @param actualTokenOut The actual amount of output tokens
     */
    event SellTokens(
        ITermMaxMarket indexed market,
        address caller,
        address recipient,
        uint128 ftInAmt,
        uint128 xtInAmt,
        ITermMaxOrder[] orders,
        uint128[] amtsToSellTokens,
        uint256 actualTokenOut
    );

    /**
     * @notice Emitted when a new gt is issued
     * @param market The address of the market
     * @param gtId The id of the gt
     * @param caller The address initiating the issue
     * @param recipient The address receiving the gt
     * @param debtTokenAmtIn The amount of debt tokens used to issue the gt
     * @param xtAmtIn The amount of xt tokens used to issue the gt
     * @param ltv The loan to value ratio
     * @param collData The collateral data
     */
    event IssueGt(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint128 debtTokenAmtIn,
        uint128 xtAmtIn,
        uint128 ltv,
        bytes collData
    );

    /**
     * @notice Emitted when a borrow operation is performed
     * @param market The address of the market
     * @param gtId The id of the gt
     * @param caller The address initiating the borrow
     * @param recipient The address receiving the borrowed tokens
     * @param collInAmt The amount of collateral tokens used
     * @param actualDebtAmt The actual amount of debt tokens borrowed
     * @param borrowAmt The amount of tokens borrowed
     */
    event Borrow(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint256 collInAmt,
        uint128 actualDebtAmt,
        uint128 borrowAmt
    );

    /**
     * @notice Emitted when a repay operation is performed through ft
     * @param market The address of the market
     * @param gtId The id of the gt
     * @param caller The address initiating the repay
     * @param recipient The address receiving the repaid tokens
     * @param repayAmt The amount of tokens repaid
     * @param returnAmt The amount of tokens returned
     */
    event RepayByTokenThroughFt(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint256 repayAmt,
        uint256 returnAmt
    );

    /**
     * @notice Emitted when a redeem and swap operation is performed
     * @param market The address of the market
     * @param ftAmount The amount of ft tokens redeemed
     * @param caller The address initiating the redeem and swap
     * @param recipient The address receiving the output tokens
     * @param actualTokenOut The actual amount of output tokens
     */
    event RedeemAndSwap(
        ITermMaxMarket indexed market, uint256 ftAmount, address caller, address recipient, uint256 actualTokenOut
    );

    /**
     * @notice Emitted when an order is created and deposited
     * @param market The address of the market
     * @param order The order created
     * @param maker The address of the maker
     * @param debtTokenToDeposit The amount of debt tokens deposited
     * @param ftToDeposit The amount of ft tokens deposited
     * @param xtToDeposit The amount of xt tokens deposited
     * @param curveCuts The curve cuts used
     */
    event CreateOrderAndDeposit(
        ITermMaxMarket indexed market,
        ITermMaxOrder indexed order,
        address maker,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        CurveCuts curveCuts
    );
}
