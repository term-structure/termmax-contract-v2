// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title ITermMaxToken
 * @notice Interface for TermMax protocol tokens that support advanced mint and burn operations
 * @dev This interface defines the standard for tokens within the TermMax ecosystem that require
 *      controlled minting and burning capabilities. It extends beyond basic ERC20 functionality
 *      to support protocol-specific operations for wrapped tokens and yield-bearing assets.
 *
 * @dev Key features:
 *      - Controlled minting for token wrapping operations
 *      - Standard burning for token unwrapping
 *      - Special burnToAToken functionality for yield token conversions
 *
 * @dev Implementation requirements:
 *      - Must implement proper access control for mint/burn operations
 *      - Should emit appropriate events for transparency
 *      - Must handle edge cases (zero amounts, invalid addresses, etc.)
 */
interface ITermMaxToken {
    /**
     * @notice Returns the address of the aToken associated with this TermMax token
     * @dev This function provides the address of the aToken that this TermMax token can be converted to.
     *      It is typically used for yield-bearing operations where TermMax tokens are converted to aTokens.
     *
     * @return The address of the associated aToken (e.g., yield-bearing token address)
     */
    function aToken() external view returns (address);

    /**
     * @notice Returns the address of the underlying asset for this TermMax token
     * @dev This function provides the address of the asset that this TermMax token represents.
     *      It is typically used to identify the underlying asset for wrapping or unwrapping operations.
     *
     * @return The address of the underlying asset (e.g., ERC20 token address)
     */
    function asset() external view returns (address);
    /**
     * @notice Mints new tokens to a specified address
     * @dev Creates new token supply and assigns it to the recipient address.
     *      This function is typically used for wrapping underlying assets into TermMax tokens
     *      or for protocol rewards distribution.
     *
     * @param to The address that will receive the newly minted tokens
     * @param amount The amount of tokens to mint (in token's smallest unit/decimals)
     *
     * @dev Requirements:
     *      - Caller must have minting permissions (typically restricted to authorized contracts)
     *      - `to` address must not be zero address
     *      - `amount` must be greater than zero
     *      - Must not exceed any maximum supply limits if implemented
     *
     * @dev Events:
     *      Should emit Transfer(address(0), to, amount) event as per ERC20 standard
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens from a specified address
     * @dev Destroys existing tokens, reducing the total supply.
     *      This function is typically used for unwrapping TermMax tokens back to underlying assets
     *      or for protocol fee collection mechanisms.
     *
     * @param to The address from which tokens will be burned
     * @param amount The amount of tokens to burn (in token's smallest unit/decimals)
     *
     * @dev Requirements:
     *      - Caller must have burning permissions (typically restricted to authorized contracts)
     *      - `to` address must have sufficient token balance
     *      - `amount` must be greater than zero and not exceed available balance
     *
     * @dev Events:
     *      Should emit Transfer(to, address(0), amount) event as per ERC20 standard
     */
    function burn(address to, uint256 amount) external;

    /**
     * @notice Burns tokens and converts them to aTokens (yield-bearing tokens)
     * @dev Special burning function that destroys TermMax tokens and simultaneously
     *      mints or transfers equivalent aTokens to the specified address. This is used
     *      for direct conversion between TermMax tokens and yield-bearing variants.
     *
     * @param to The address that will receive the resulting aTokens
     * @param amount The amount of tokens to burn and convert (in token's smallest unit/decimals)
     *
     * @dev Requirements:
     *      - Caller must have burning permissions
     *      - `to` address must not be zero address
     *      - `amount` must be greater than zero and not exceed available balance
     *      - Underlying aToken contract must be properly configured and functional
     *
     * @dev Implementation notes:
     *      - Conversion rate between burned tokens and minted aTokens should be clearly defined
     *      - May involve external calls to aToken contracts
     *      - Should handle potential failures in aToken minting gracefully
     *
     * @dev Events:
     *      Should emit both burn and aToken mint events for full transparency
     */
    function burnToAToken(address to, uint256 amount) external;
}
