// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMintableERC20, IERC20} from "../tokens/IMintableERC20.sol";
import {IGearingToken} from "../tokens/IGearingToken.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {MarketConfig} from "../storage/TermMaxStorage.sol";

/**
 * @title Market Events Interface
 * @notice Events emitted by the TermMax market operations
 */
interface MarketEvents {
    /**
     * @notice Emitted when a market is initialized
     * @param collateral The collateral token address
     * @param underlying The underlying token address
     * @param maturity The unix timestamp of the maturity date
     * @param ft The TermMax Market FT token
     * @param xt The TermMax Market XT token
     * @param gt The Gearing token
     */
    event MarketInitialized(
        address indexed collateral,
        IERC20 indexed underlying,
        uint64 maturity,
        IMintableERC20 ft,
        IMintableERC20 xt,
        IGearingToken gt
    );

    /**
     * @notice Emitted when the market configuration is updated
     * @param config The new market configuration
     */
    event UpdateMarketConfig(MarketConfig config);

    /**
     * @notice Emitted when tokens are minted
     * @param caller The address initiating the mint
     * @param receiver The address receiving the minted tokens
     * @param amount The amount of tokens minted
     */
    event Mint(address indexed caller, address indexed receiver, uint256 amount);

    /**
     * @notice Emitted when tokens are burned
     * @param caller The address initiating the burn
     * @param receiver The address whose tokens are burned
     * @param amount The amount of tokens burned
     */
    event Burn(address indexed caller, address indexed receiver, uint256 amount);

    /**
     * @notice Emitted when a leveraged position is created
     * @param loanReceiver The address receiving the loan
     * @param gtReceiver The address receiving the Gearing Token
     * @param gtId The ID of the Gearing Token
     * @param debtAmt The amount of debt in underlying token
     * @param xtAmt The amount of XT token
     * @param fee The amount of minting gt fee, unit by FT token
     * @param collateralData The encoded collateral data
     */
    event LeverageByXt(
        address indexed loanReceiver,
        address indexed gtReceiver,
        uint256 indexed gtId,
        uint128 debtAmt,
        uint256 xtAmt,
        uint128 fee,
        bytes collateralData
    );

    /**
     * @notice Emitted when FT is issued using collateral
     * @param caller The address initiating the issuance
     * @param recipient The address receiving the FT
     * @param gtId The ID of the Gearing Token
     * @param debtAmt The amount of debt in underlying token
     * @param ftAmt The amount of FT issued
     * @param fee The amount of minting gt fee, unit by FT token
     * @param collateralData The encoded collateral data
     */
    event IssueFt(
        address indexed caller,
        address indexed recipient,
        uint256 indexed gtId,
        uint128 debtAmt,
        uint128 ftAmt,
        uint128 fee,
        bytes collateralData
    );

    /**
     * @notice Emitted when FT is issued using existed Gearing Token
     * @param caller The address initiating the issuance
     * @param recipient The address receiving the FT
     * @param gtId The ID of the Gearing Token
     * @param debtAmt The amount of debt in underlying token
     * @param ftAmt The amount of FT issued
     * @param issueFee The amount of issuing fee, unit by FT token
     */
    event IssueFtByExistedGt(
        address indexed caller,
        address indexed recipient,
        uint256 indexed gtId,
        uint128 debtAmt,
        uint128 ftAmt,
        uint128 issueFee
    );

    /**
     * @notice Emitted when tokens are redeemed
     * @param caller The address initiating the redemption
     * @param recipient The address receiving the redeemed tokens
     * @param proportion The proportion of underlying token and collateral should be deliveried
     *                   base 1e16 decimals
     * @param underlyingAmt The amount of underlying received
     * @param deliveryData The encoded data of collateral received
     */
    event Redeem(
        address indexed caller, address indexed recipient, uint128 proportion, uint128 underlyingAmt, bytes deliveryData
    );

    /**
     * @notice Emitted when an order is created
     * @param maker The maker of the order
     * @param order The order
     */
    event CreateOrder(address indexed maker, ITermMaxOrder indexed order);
}
