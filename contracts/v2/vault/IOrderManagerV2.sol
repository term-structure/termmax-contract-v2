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
     * @notice Update the configuration for multiple orders
     * @param orders The list of order addresses to update
     * @param orderConfigs The new configuration parameters for each order, containing:
     *                    - virtualXtReserve: The new virtual XT reserve for the order
     *                    - maxXtReserve: The new maximum XT reserve for the order
     *                    - removingLiquidity: The amount of liquidity to remove from the order
     *                    - curveCuts: The new curve cuts for the order
     */
    function updateOrdersConfiguration(address[] memory orders, OrderV2ConfigurationParams[] memory orderConfigs)
        external;

    /**
     * @notice Remove the liquidity from multiple orders
     * @param asset The asset to be added as liquidity, debt token or pool shares
     * @param orders The list of order addresses to update
     * @param removedLiquidities The amount of liquidity to remove from each order
     */
    function removeLiquidityFromOrders(IERC20 asset, address[] memory orders, uint256[] memory removedLiquidities)
        external;

    /**
     * @notice Create a new order with the specified parameters
     * @param market The market address
     * @param params The configuration parameters for the new order
     * @return order The address of the newly created order
     */
    function createOrder(ITermMaxMarketV2 market, OrderV2ConfigurationParams memory params)
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

    /**
     * @notice Withdraw ft token instead of underlying token
     * @param order The address of the order to withdraw from
     * @param amount The amount of ft tokens
     * @param recipient The recipient
     */
    function withdrawFts(address order, uint256 amount, address recipient) external;

    function afterSwap(IERC20 asset, uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256 deltaXt) external;
}
