// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "../v1/tokens/IMintableERC20.sol";
import {OrderInitialParams} from "./storage/TermMaxStorageV2.sol";
import {ISwapCallback} from "../v1/ISwapCallback.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {CurveCuts} from "../v1/storage/TermMaxStorage.sol";

/**
 * @title TermMax Order interface v2
 * @author Term Structure Labs
 * @notice The V2 Order use vitual xt reserve to present the current price,
 *        which is different from V1 Order that uses real xt reserve.
 *        You have to set the virtual xt reserve to set an initialize price.
 */
interface ITermMaxOrderV2 {
    /// @notice Initialize the token and configuration of the order (V2 version)
    function initialize(OrderInitialParams memory params) external;

    // =============================================================================
    // V2-SPECIFIC VIEW FUNCTIONS
    // =============================================================================

    /// @notice Get the pool address set for the order
    function pool() external view returns (IERC4626);

    /// @notice Get the virtual XT reserve, which is used to present the current price
    function virtualXtReserve() external view returns (uint256);

    /// @notice Get real reserves including assets in pool
    function getRealReserves() external view returns (uint256 ftReserve, uint256 xtReserve);

    // =============================================================================
    // V2-SPECIFIC ADMIN FUNCTIONS
    // =============================================================================

    /// @notice Set curve configuration
    function setCurve(CurveCuts memory newCurveCuts) external;

    /// @notice Set general configuration parameters
    /// @param gtId The ID of the Gearing Token, which is used to borrow tokens
    /// @param maxXtReserve The maximum reserve of XT token
    /// @param swapTrigger The callback contract to trigger swaps
    /// @param virtualXtReserve The virtual reserve of XT token, which presents the current price
    function setGeneralConfig(uint256 gtId, uint256 maxXtReserve, ISwapCallback swapTrigger, uint256 virtualXtReserve)
        external;

    /// @notice Set the staking pool
    /// @param newPool The new staking pool to be set, the address(0) can be used to unset the pool
    function setPool(IERC4626 newPool) external;

    // =============================================================================
    // V2-SPECIFIC LIQUIDITY MANAGEMENT FUNCTIONS
    // =============================================================================

    /// @notice Add liquidity to the order
    /// @notice If you want to add liquidity by ft or xt, please transfer them to the order directly.
    /// @param asset The asset to be added as liquidity, debt token or pool shares
    /// @param amount The amount of the asset to be added
    function addLiquidity(IERC20 asset, uint256 amount) external;

    /// @notice Remove liquidity from the order
    /// @param asset The asset to be removed as liquidity, debt token or pool shares
    /// @param amount The amount of the asset to be removed
    /// @param recipient The address to receive the removed liquidity
    function removeLiquidity(IERC20 asset, uint256 amount, address recipient) external;

    /// @notice Redeem all assets and close the order, must be called after the maturity + liquidation period
    /// @param asset The asset to be redeemed, debt token or pool shares
    /// @param recipient The address to receive the redeemed assets
    /// @return badDebt The amount of bad debt incurred during the redemption
    /// @return deliveryData Additional data returned from the redemption process
    /// @dev You have to withdraw the delivery collateral manually if the asset is a pool share.
    /// @dev This function will close the order and transfer all assets to the recipient.
    function redeemAll(IERC20 asset, address recipient) external returns (uint256 badDebt, bytes memory deliveryData);
}
