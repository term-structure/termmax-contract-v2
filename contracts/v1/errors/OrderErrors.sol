// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Order Errors Interface
 * @notice Custom errors for the TermMax order operations
 */
interface OrderErrors {
    /**
     * @notice Error thrown when attempting to interact with an order before its term is open
     */
    error TermIsNotOpen();

    /**
     * @notice Error thrown when attempting to swap between unsupported token pairs
     * @param tokenIn The input token
     * @param tokenOut The output token
     */
    error CantNotSwapToken(IERC20 tokenIn, IERC20 tokenOut);

    /**
     * @notice Error thrown when attempting to swap a token for itself
     */
    error CantSwapSameToken();

    /**
     * @notice Error thrown when attempting to issue FT without a corresponding GT
     */
    error CantNotIssueFtWithoutGt();

    /**
     * @notice Error thrown when the curve cuts parameters are invalid
     */
    error InvalidCurveCuts();

    /**
     * @notice Error thrown when borrowing is not allowed in the current state
     */
    error BorrowIsNotAllowed();

    /**
     * @notice Error thrown when lending is not allowed in the current state
     */
    error LendIsNotAllowed();

    /**
     * @notice Error thrown when a non-market attempts to perform a market-only action
     */
    error OnlyMarket();

    /**
     * @notice Error thrown when a swap transaction is submitted after its deadline
     */
    error DeadlineExpired();

    /**
     * @notice Error thrown when a GT hasn't been approved for an operation
     * @param gtId The ID of the unapproved GT
     */
    error GtNotApproved(uint256 gtId);

    /**
     * @notice Error thrown when the XT reserve exceeds the maximum allowed
     */
    error XtReserveTooHigh();

    /**
     * @notice Error thrown when the actual output amount doesn't match the expected amount
     * @param expectedAmt The expected amount
     * @param actualAmt The actual amount received
     */
    error UnexpectedAmount(uint256 expectedAmt, uint256 actualAmt);

    /**
     * @notice Error thrown when attempting to redeem before the final liquidation deadline
     * @param liquidationDeadline The timestamp after which redemption is allowed
     */
    error CanNotRedeemBeforeFinalLiquidationDeadline(uint256 liquidationDeadline);

    /**
     * @notice Error thrown when attempting an operation that requires evacuation mode when it's not active
     */
    error EvacuationIsNotActived();

    /**
     * @notice Error thrown when attempting an operation that's not allowed during evacuation mode
     */
    error EvacuationIsActived();

    /**
     * @notice Error thrown when there isn't enough excess FT or XT to complete a withdrawal
     */
    error NotEnoughFtOrXtToWithdraw();
}
