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

    /// @notice Emitted when the order curve is updated
    event CurveUpdated(CurveCuts curveCuts);

    /// @notice Emitted when the staking pool is updated
    event PoolUpdated(address indexed pool);

    /// @notice Emitted when the general configuration of the order is updated
    /// @param gtId The ID of the Gearing Token, which is used to borrow tokens
    /// @param maxXtReserve The maximum reserve of XT token
    /// @param swapTrigger The callback contract to trigger after swaps
    /// @param virtualXtReserve The virtual reserve of XT token, which presents the current price
    event GeneralConfigUpdated(uint256 gtId, uint256 maxXtReserve, ISwapCallback swapTrigger, uint256 virtualXtReserve);

    /// @notice Emitted when liquidity is added to the order
    /// @param asset The asset that was added as liquidity, either debt token or pool shares
    /// @param amount The amount of the asset that was added
    event LiquidityAdded(IERC20 indexed asset, uint256 amount);

    /// @notice Emitted when liquidity is removed from the order
    /// @param asset The asset that was removed as liquidity, either debt token or pool shares
    /// @param amount The amount of the asset that was removed
    event LiquidityRemoved(IERC20 indexed asset, uint256 amount);
}
