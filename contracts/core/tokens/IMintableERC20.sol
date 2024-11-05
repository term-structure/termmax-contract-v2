// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Term Max ERC20 token interface
 * @author Term Structure Labs
 */
interface IMintableERC20 is IERC20 {
    /// @notice Error when using offline signature but spender is not the maerket
    error SpenderIsNotMarket(address spender);

    /// @notice Mint this token to an address
    /// @param to The address receiving token
    /// @param amount The amount of token minted
    /// @dev Only the market can mint Term Max tokens
    function mint(address to, uint256 amount) external;

    /// @notice Return the market's address
    function marketAddr() external view returns (address);

    /// @notice Burn tokens from sender
    /// @param amount The number of tokens to be burned
    /// @dev Only the market can burn Term Max tokens
    function burn(uint256 amount) external;

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}
