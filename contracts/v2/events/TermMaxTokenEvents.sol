// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface TermMaxTokenEvents {
    event TermMaxTokenInitialized(address indexed admin, address indexed underlying);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed to, uint256 amount);
    event WithdrawIncome(address indexed to, uint256 amount);
    event UpdateBufferConfig(uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer);

    /// @notice Event emitted when a new implementation upgrade is submitted with timelock
    event SubmitUpgrade(address indexed newImplementation, uint64 validAt);

    /// @notice Event emitted when a pending upgrade is accepted
    event AcceptUpgrade(address indexed caller, address indexed newImplementation);

    /// @notice Event emitted when a pending upgrade is revoked
    event RevokeUpgrade(address indexed caller);
}
