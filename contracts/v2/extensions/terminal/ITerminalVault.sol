// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITerminalVault {
    /**
     * @notice redeem mToken to tokenOut if daily limit and allowance not exceeded
     * Burns mTBILL from the user.
     * Transfers fee in mToken to feeReceiver
     * Transfers tokenOut to user.
     * @param tokenOut stable coin token address to redeem to
     * @param amountMTokenIn amount of mTBILL to redeem (decimals 18)
     * @param minReceiveAmount minimum expected amount of tokenOut to receive (decimals 18)
     */
    function redeemInstant(address tokenOut, uint256 amountMTokenIn, uint256 minReceiveAmount) external;

    /**
     * @notice deposit tokenIn to mint mToken if daily limit and allowance not exceeded
     * Transfers tokenIn from the user.
     * Transfers fee in tokenIn to feeReceiver
     * Mints mTBILL to user.
     * @param tokenIn stable coin token address to deposit
     * @param amountToken amount of tokenIn to deposit (decimals 18)
     * @param minReceiveAmount minimum expected amount of mToken to receive (decimals 18)
     * @param referrerId referrer id for tracking
     */
    function depositInstant(address tokenIn, uint256 amountToken, uint256 minReceiveAmount, bytes32 referrerId)
        external;
}
