// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface FactoryEvents {
    /// @notice Emit when setting implementations of Gearing Token
    event SetGtImplement(bytes32 key, address gtImplement);

    /// @notice Emit when creating a new market
    event CreateMarket(address indexed market, address indexed collateral, IERC20 indexed debtToken);
}
