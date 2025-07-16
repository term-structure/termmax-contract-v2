// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {CurveCuts} from "../../v1/storage/TermMaxStorage.sol";
import {OrderV2ConfigurationParams} from "./VaultStorageV2.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {ITermMaxOrderV2} from "../ITermMaxOrderV2.sol";

interface IOrderManagerV2 {
    /**
     * @notice Update the curve configuration for multiple orders
     * @param orders The list of order addresses to update
     * @param newCurveCuts The new curve configuration parameters
     */
    function updateOrderCurves(address[] memory orders, CurveCuts[] memory newCurveCuts) external;

    /**
     * @notice Update the general configuration and liquidity for multiple orders
     * @param asset The asset to be added as liquidity, debt token or pool shares
     * @param orders The list of order addresses to update
     * @param params The new configuration parameters for each order
     */
    function updateOrdersConfigAndLiquidity(
        IERC20 asset,
        address[] memory orders,
        OrderV2ConfigurationParams[] memory params
    ) external;

    /**
     * @notice Create a new order with the specified parameters
     * @param market The market address
     * @param params The configuration parameters for the new order
     * @param curveCuts The curve cuts for the new order
     * @return order The address of the newly created order
     */
    function createOrder(ITermMaxMarketV2 market, OrderV2ConfigurationParams memory params, CurveCuts memory curveCuts)
        external
        returns (ITermMaxOrderV2 order);

    /**
     * @notice Withdraw assets from an order after maturity
     * @param asset The asset token address
     * @param order The address of the order to withdraw from
     * @return badDebt The amount of bad debt incurred
     * @return deliveryCollateral The amount of collateral delivered
     */
    function redeemOrder(IERC20 asset, address order) external returns (uint256 badDebt, uint256 deliveryCollateral);

    function afterSwap(IERC20 asset, uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256 deltaXt) external;
}
