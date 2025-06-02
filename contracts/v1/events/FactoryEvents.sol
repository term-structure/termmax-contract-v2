// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultInitialParams} from "../storage/TermMaxStorage.sol";

/**
 * @title Factory Events Interface
 * @notice Events emitted by the TermMax factory contracts
 */
interface FactoryEvents {
    /**
     * @notice Emitted when a new Gearing Token implementation is set
     * @param key The unique identifier for the GT implementation
     * @param gtImplement The address of the GT implementation contract
     */
    event SetGtImplement(bytes32 key, address gtImplement);

    /**
     * @notice Emitted when a new market is created
     * @param market The address of the newly created market
     * @param collateral The address of the collateral token
     * @param debtToken The debt token interface
     */
    event CreateMarket(address indexed market, address indexed collateral, IERC20 indexed debtToken);

    /**
     * @notice Emitted when a new vault is created
     * @param vault The address of the newly created vault
     * @param creator The address of the vault creator
     * @param initialParams The initial parameters used to configure the vault
     */
    event CreateVault(address indexed vault, address indexed creator, VaultInitialParams indexed initialParams);
}
