// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface MakerHelperEvents {
    /// @notice Emitted when an order is placed via MakerHelper
    /// @param maker The address of the maker placing the order
    /// @param market The address of the market where the order is placed
    /// @param order The address of the created order
    /// @param gtId The ID of the minted GT token
    /// @param debtTokenToDeposit The amount of debt tokens deposited
    /// @param ftToDeposit The amount of FT tokens deposited
    /// @param xtToDeposit The amount of XT tokens deposited
    event OrderPlaced(
        address indexed maker,
        address indexed market,
        address order,
        uint256 gtId,
        uint256 debtTokenToDeposit,
        uint256 ftToDeposit,
        uint256 xtToDeposit
    );

    /// @notice Emitted when ft and xt tokens are minted via MakerHelper
    /// @param market The address of the market where the tokens are minted
    /// @param recipient The address receiving the minted tokens
    /// @param amount The amount of tokens minted
    event MintTokens(address indexed market, address indexed recipient, uint256 amount);

    /// @notice Emitted when ft and xt tokens are burned via MakerHelper
    /// @param market The address of the market where the tokens are burned
    /// @param recipient The address receiving the underlying asset from the burn
    /// @param amount The amount of tokens burned
    event BurnTokens(address indexed market, address indexed recipient, uint256 amount);
}
