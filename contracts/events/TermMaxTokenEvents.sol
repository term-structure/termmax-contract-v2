// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface TermMaxTokenEvents {
    event TermMaxTokenInitialized(address indexed admin, address indexed underlying);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed to, uint256 amount);
    event WithdrawIncome(address indexed to, uint256 amount);
    event UpdateBufferConfig(uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer);
}
