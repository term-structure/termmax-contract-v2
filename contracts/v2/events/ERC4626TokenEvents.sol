// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Events for ERC4626 Token Contract
 * @author Term Structure Labs
 */
interface ERC4626TokenEvents {
    /**
     * @notice Emitted when a token is initialized
     * @dev Fired during the initial setup of a ERC4626ForAave contract
     * @param admin The address of the administrator managing the token
     * @param underlying The address of the underlying asset (e.g., USDC for tmxUSDC)
     * @param isStable Indicates if the erc4626 share is a stable to its underlying asset
     */
    event ERC4626ForAaveInitialized(address indexed admin, address indexed underlying, bool isStable);

    /**
     * @notice Emitted when a token is initialized
     * @dev Fired during the initial setup of a TermMax token contract
     * @param admin The address of the administrator managing the token
     * @param underlying The address of the underlying asset (e.g., USDC for tmxUSDC)
     * @param pool The address of the third pool
     */
    event ERC4626For4626Initialized(address indexed admin, address indexed underlying, address indexed pool);

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
     * @notice Emitted when a customized ERC4626 token is initialized
     * @param admin The address of the administrator managing the token
     * @param underlying The address of the underlying asset (e.g., USDC)
     * @param pool The address of the third pool
     */
    event ERC4626ForCustomizeInitialized(address indexed admin, address indexed underlying, address indexed pool);

    /**
     * @notice Emitted when assets (non-underlying) are withdrawn from the token contract
     * @dev Allows the owner to recover tokens mistakenly sent to the contract
     * @param token The address of the token being withdrawn
     * @param operator The address initiating the withdrawal
     * @param recipient The address receiving the withdrawn assets
     * @param amount The amount of assets withdrawn
     */
    event WithdrawAssets(IERC20 indexed token, address indexed operator, address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when a venus pool is initialized
     * @dev Fired during the initial setup of a ERC4626ForVenus contract
     * @param admin The address of the administrator managing the token
     * @param underlying The address of the underlying asset (e.g., USDC for tmxUSDC)
     * @param pool The address of the third pool
     */
    event ERC4626ForVenusInitialized(address indexed admin, address indexed underlying, address indexed pool);
}
