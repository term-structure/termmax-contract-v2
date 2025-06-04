// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";

/**
 * @title Order Manager Interface
 * @author Term Structure Labs
 */
interface IOrderManager {
    /**
     * @notice Creates a new order
     * @param asset The asset token address
     * @param market The market address
     * @param maxSupply The maximum xt supply of the order
     * @param initialReserve The initial reserve of the order
     * @param curveCuts The curve cuts for the order
     * @return order The order address
     */
    function createOrder(
        IERC20 asset,
        ITermMaxMarket market,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external returns (ITermMaxOrder order);

    /**
     * @notice Deals bad debt
     * @param recipient The recipient of the collateral token
     * @param collateral The collateral token address
     * @param amount The amount of bad debt to deal
     */
    function dealBadDebt(address recipient, address collateral, uint256 amount)
        external
        returns (uint256 collateralOut);

    /**
     * @notice Updates multiple orders
     * @param asset The asset token address
     * @param orders The orders to update
     * @param changes The changes to apply to each order
     * @param maxSupplies The maximum xt supplies to update for each order
     * @param curveCuts The curve cuts to update for each order
     */
    function updateOrders(
        IERC20 asset,
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        CurveCuts[] memory curveCuts
    ) external;

    /**
     * @notice Withdraws performance fee
     * @param asset The asset token address
     * @param recipient The recipient of the performance fee
     * @param amount The amount of performance fee to withdraw
     */
    function withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) external;

    /**
     * @notice Deposits assets
     * @param asset The asset token address
     * @param amount The amount of assets to deposit
     */
    function depositAssets(IERC20 asset, uint256 amount) external;

    /**
     * @notice Withdraws assets
     * @param asset The asset token address
     * @param recipient The recipient of the assets
     * @param amount The amount of assets to withdraw
     */
    function withdrawAssets(IERC20 asset, address recipient, uint256 amount) external;

    /**
     * @notice Accrues interest
     */
    function accruedInterest() external;

    /**
     * @notice Redeems an order
     * @param order The order to redeem
     */
    function redeemOrder(ITermMaxOrder order) external;

    /**
     * @notice Swaps callback to calculate interest
     * @param ftReserve The reserve of the FT token
     * @param xtReserve The reserve of the XT token
     * @param deltaFt The deltaFt of the swap
     */
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt) external;
}
