// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITUSDEVault {
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
}
