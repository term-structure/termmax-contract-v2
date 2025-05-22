// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface TermMaxTokenErrors {
    error InvalidToken();
    error InsufficientIncomeAmount(uint256 availableAmount, uint256 requestedAmount);
    error AaveWithdrawFailed(uint256 aTokenAmount, uint256 recieivedAmount);
}
