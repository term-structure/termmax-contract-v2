// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OrderConfig, CurveCuts, ISwapCallback} from "../../v1/storage/TermMaxStorage.sol";

/**
 * @title Order Events v2
 * @author Term Structure Labs
 */
interface OrderEventsV2 {
    /// @notice Emitted when an order is initialized
    /// @param maker The address of the maker who created the order
    /// @param market The address of the market associated with the order
    event OrderInitialized(address indexed maker, address indexed market);

    /// @notice Emitted when the staking or reward pool associated with the order is changed
    /// @param pool The address of the new staking/reward pool contract
    event PoolUpdated(address indexed pool);

    /// @notice Emitted when the general configuration of the order is updated
    /// @dev These parameters control borrowing (gtId), swap callbacks (swapTrigger)
    /// @param gtId The ID of the Gearing Token, which is used to borrow tokens
    /// @param swapTrigger The callback contract to trigger after swaps
    event GeneralConfigUpdated(uint256 gtId, ISwapCallback swapTrigger);

    /// @notice Emitted when the curve configuration and price parameters are updated
    /// @dev Curve cuts define the pricing curve for lending/borrowing; virtualXtReserve
    ///      sets the current price level; maxXtReserve limits exposure
    /// @param virtualXtReserve The virtual reserve of XT token, which presents the current price
    /// @param maxXtReserve The maximum reserve of XT token
    /// @param curveCuts The new curve configuration parameters
    event CurveAndPriceUpdated(uint256 virtualXtReserve, uint256 maxXtReserve, CurveCuts curveCuts);

    /// @notice Emitted when liquidity is added to the order
    /// @dev The asset can be either a debt token (FT) or pool share token (LP/token representing liquidity)
    /// @param asset The asset that was added as liquidity, either debt token or pool shares
    /// @param amount The amount of the asset that was added
    event LiquidityAdded(IERC20 indexed asset, uint256 amount);

    /// @notice Emitted when liquidity is removed from the order
    /// @dev Removal may occur during normal withdrawals or as part of liquidation/settlement flows
    /// @param asset The asset that was removed as liquidity, either debt token or pool shares
    /// @param amount The amount of the asset that was removed
    event LiquidityRemoved(IERC20 indexed asset, uint256 amount);

    /// @notice Emitted when assets are redeemed from the order at maturity or during settlement
    /// @dev deliveryData is arbitrary data passed to the recipient to help with off-chain processing or callbacks
    /// @param recipient The address receiving the redeemed assets
    /// @param debtTokenAmount The amount of debt tokens redeemed
    /// @param badDebt Any unrecoverable/delegated bad debt remaining after redemption
    /// @param deliveryData Extra data related to delivery or redemption (opaque to the contract)
    event Redeemed(address indexed recipient, uint256 debtTokenAmount, uint256 badDebt, bytes deliveryData);

    /// @notice Emitted when all positions are redeemed before maturity (early settlement)
    /// @dev This event provides the split of redeemed amounts into debt token, FT and XT components
    /// @param recipient The address receiving the redeemed assets
    /// @param debtTokenAmount The amount of debt tokens redeemed
    /// @param ftAmount The amount of FT (fixed-term) tokens redeemed
    /// @param xtAmount The amount of XT (variable-term) tokens redeemed
    event RedeemedAllBeforeMaturity(
        address indexed recipient, uint256 debtTokenAmount, uint256 ftAmount, uint256 xtAmount
    );

    /// @notice Emitted when tokens are borrowed from the order
    /// @param recipient The address receiving the borrowed tokens
    /// @param amount The amount of tokens borrowed
    event Borrowed(address indexed recipient, uint256 amount);
}
