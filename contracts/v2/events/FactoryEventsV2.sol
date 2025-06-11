// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MarketInitialParams} from "../../v1/storage/TermMaxStorage.sol";
import {VaultInitialParamsV2} from "../storage/TermMaxStorageV2.sol";

/**
 * @title Factory Events Interface V2
 * @notice Events emitted by the TermMax factory contracts
 */
interface FactoryEventsV2 {
    /**
     * @notice Emitted when a new market is created
     * @param market The address of the newly created market
     * @param collateral The address of the collateral token
     * @param debtToken The debt token interface
     * @param params The initial parameters for the market
     */
    event CreateMarket(
        address indexed market, address indexed collateral, IERC20 indexed debtToken, MarketInitialParams params
    );

    /**
     * @notice Emitted when a new vault is created
     * @param vault The address of the newly created vault
     * @param creator The address of the vault creator
     * @param initialParams The initial parameters used to configure the vault
     */
    event CreateVault(address indexed vault, address indexed creator, VaultInitialParamsV2 initialParams);

    /**
     * @notice Emitted when a new price feed is created
     * @param priceFeed The address of the newly created price feed contract
     */
    event PriceFeedCreated(address indexed priceFeed);
}
