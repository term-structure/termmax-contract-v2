// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TermMax ERC20 token interface
 * @author Term Structure Labs
 */
interface IMintableERC20 is IERC20 {
    /// @notice Error when using offline signature but spender is not the maerket
    error SpenderIsNotMarket(address spender);

    // @notice Initial function
    /// @param name The token's name
    /// @param symbol The token's symbol
    /// @param _decimals The token's decimals
    function initialize(string memory name, string memory symbol, uint8 _decimals) external;

    /// @notice Mint this token to an address
    /// @param to The address receiving token
    /// @param amount The amount of token minted
    /// @dev Only the market can mint TermMax tokens
    function mint(address to, uint256 amount) external;

    /// @notice Return the market's address
    function marketAddr() external view returns (address);

    /// @notice Burn tokens from sender
    /// @param amount The number of tokens to be burned
    /// @dev Only the market can burn TermMax tokens
    function burn(uint256 amount) external;

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}
