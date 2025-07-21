// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title TermMax ERC20 token interface
 * @author Term Structure Labs
 */
interface IMintableERC20V2 {
    /// @notice Burn tokens from owner, allowing spender to burn the tokens
    /// @param owner The address of the token holder
    /// @param spender The address of the token spender
    /// @param amount The number of tokens to be burned
    /// @dev Only the market can burn TermMax tokens
    function burn(address owner, address spender, uint256 amount) external;
}
