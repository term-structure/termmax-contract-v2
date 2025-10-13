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
    event MarketCreated(
        address indexed market, address indexed collateral, IERC20 indexed debtToken, MarketInitialParams params
    );

    /**
     * @notice Emitted when a new vault is created
     * @param vault The address of the newly created vault
     * @param creator The address of the vault creator
     * @param initialParams The initial parameters used to configure the vault
     */
    event VaultCreated(address indexed vault, address indexed creator, VaultInitialParamsV2 initialParams);

    /**
     * @notice Emitted when a new price feed is created
     * @param priceFeed The address of the newly created price feed contract
     */
    event PriceFeedCreated(address indexed priceFeed);

    // Events from TermMax4626Factory
    /**
     * @notice Emitted when TermMax4626Factory is initialized
     * @param aavePool The Aave pool address
     * @param aaveReferralCode The Aave referral code
     * @param stableERC4626For4626Implementation The stable ERC4626For4626 implementation address
     * @param stableERC4626ForAaveImplementation The stable ERC4626ForAave implementation address
     * @param variableERC4626ForAaveImplementation The variable ERC4626ForAave implementation address
     */
    event TermMax4626FactoryInitialized(
        address indexed aavePool,
        uint16 aaveReferralCode,
        address stableERC4626For4626Implementation,
        address stableERC4626ForAaveImplementation,
        address variableERC4626ForAaveImplementation
    );

    /**
     * @notice Emitted when a new StableERC4626For4626 is created
     * @param caller The address that called the creation function
     * @param stableERC4626For4626 The address of the created StableERC4626For4626
     */
    event StableERC4626For4626Created(address indexed caller, address indexed stableERC4626For4626);

    /**
     * @notice Emitted when a new StableERC4626ForAave is created
     * @param caller The address that called the creation function
     * @param stableERC4626ForAave The address of the created StableERC4626ForAave
     */
    event StableERC4626ForAaveCreated(address indexed caller, address indexed stableERC4626ForAave);

    /**
     * @notice Emitted when a new VariableERC4626ForAave is created
     * @param caller The address that called the creation function
     * @param variableERC4626ForAave The address of the created VariableERC4626ForAave
     */
    event VariableERC4626ForAaveCreated(address indexed caller, address indexed variableERC4626ForAave);
}
