// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {CurveCuts} from "contracts/storage/TermMaxStorage.sol";

interface IOrderManager {
    function createOrder(
        IERC20 asset,
        ITermMaxMarket market,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external returns (ITermMaxOrder order);

    function dealBadDebt(
        address recipient,
        address collaretal,
        uint256 amount
    ) external returns (uint256 collateralOut);

    function updateOrders(
        IERC20 asset,
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        CurveCuts[] memory curveCuts
    ) external;

    function withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) external;

    function depositAssets(IERC20 asset, uint256 amount) external;

    function withdrawAssets(IERC20 asset, address recipient, uint256 amount) external;

    function redeemOrder(ITermMaxOrder order) external;

    function swapCallback(int256 deltaFt) external;
}
