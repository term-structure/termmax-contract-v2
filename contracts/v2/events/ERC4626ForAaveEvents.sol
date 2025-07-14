// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Events for ERC4626ForAave
 * @author Term Structure Labs
 * @notice Interface defining events for TermMax token operations and lifecycle management
 * @dev Contains events for token initialization, minting/burning, income withdrawal, buffer management, and upgrade processes
 */
interface ERC4626ForAaveEvents {
    /**
     * @notice Emitted when a  token is initialized
     * @dev Fired during the initial setup of a TermMax token contract
     * @param admin The address of the administrator managing the token
     * @param underlying The address of the underlying asset (e.g., USDC for tmxUSDC)
     * @param isStable Indicates if the erc4626 share is a stable to its underlying asset
     */
    event ERC4626ForAaveInitialized(address indexed admin, address indexed underlying, bool isStable);

    /**
     * @notice Emitted when income is withdrawn from the token contract
     * @dev Tracks income distribution events, typically from yield-generating activities
     * @param to The recipient address receiving the income withdrawal
     * @param amount The amount of income withdrawn (in underlying asset denomination)
     */
    event WithdrawIncome(address indexed to, uint256 amount);

    /**
     * @notice Emitted when buffer configuration parameters are updated
     * @dev Buffer configuration manages reserve levels for operational stability
     * @param minimumBuffer The minimum buffer threshold required
     * @param maximumBuffer The maximum buffer threshold allowed
     * @param buffer The current buffer amount after the update
     */
    event UpdateBufferConfig(uint256 minimumBuffer, uint256 maximumBuffer, uint256 buffer);

    /**
     * @notice Event emitted when a new implementation upgrade is submitted with timelock
     * @dev Part of the upgrade mechanism that requires timelock for security
     * @param newImplementation The address of the new implementation contract
     * @param validAt The timestamp when the upgrade can be executed (after timelock period)
     */
    event SubmitUpgrade(address indexed newImplementation, uint64 validAt);

    /**
     * @notice Event emitted when a pending upgrade is accepted
     * @dev Confirms successful execution of a previously submitted upgrade
     * @param caller The address that executed the upgrade acceptance
     * @param newImplementation The address of the implementation that was activated
     */
    event AcceptUpgrade(address indexed caller, address indexed newImplementation);

    /**
     * @notice Event emitted when a pending upgrade is revoked
     * @dev Allows cancellation of a pending upgrade before execution
     * @param caller The address that revoked the pending upgrade
     */
    event RevokeUpgrade(address indexed caller);
}
