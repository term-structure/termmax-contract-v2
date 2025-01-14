// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PendingLib, PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {VaultErrors} from "../errors/VaultErrors.sol";
import {VaultEvents} from "../events/VaultEvents.sol";
import {ITermMaxRouter} from "../router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {VaultConstants} from "../lib/VaultConstants.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";
import {ISwapCallback} from "../ISwapCallback.sol";
import {Constants} from "../lib/Constants.sol";
import {ArrayUtils} from "../lib/ArrayUtils.sol";
import {OrderConfig, CurveCuts} from "../storage/TermMaxStorage.sol";
import {MathLib} from "../lib/MathLib.sol";

abstract contract OrderManager is VaultErrors, VaultEvents, ISwapCallback {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using ArrayUtils for address[];
    using MathLib for uint256;

    struct OrderInfo {
        ITermMaxMarket market;
        IERC20 ft;
        IERC20 xt;
        uint128 maxSupply;
        uint128 ftReserve;
        uint64 maturity;
    }

    uint256 public totalFt;
    // locked ft = lpersFt + curatorIncentive;
    uint256 public lpersFt;
    uint256 public curatorIncentive;
    uint64 private lastUpdateTime;
    uint64 term;
    uint64 maxTerm = 90;
    uint64 curatorPercentage;

    address[] public supplyQueue;
    mapping(address => OrderInfo) public orderMapping;
    mapping(address => uint256) public badDebtMapping;

    address[] public withdrawQueue;

    /// @notice Calculate how many days until expiration
    function _daysToMaturity() internal view returns (uint256) {
        return maxTerm;
    }

    function asset() public view virtual returns (address);

    function createOrder(
        ITermMaxMarket market,
        uint256 maxXtReserve,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external virtual returns (ITermMaxOrder order);

    function updateOrders(
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        uint256[] memory maxXtReserves,
        CurveCuts[] memory curveCuts
    ) external virtual;

    function updateSupplyQueue(uint256[] memory indexes) external virtual;

    function updateWithdrawQueue(uint256[] memory indexes) external virtual;

    function redeemOrder(ITermMaxOrder order) external virtual;

    function withdrawIncentive(address recipient, uint256 amount) external virtual;

    function _createOrder(
        ITermMaxMarket market,
        uint256 maxXtReserve,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) internal returns (ITermMaxOrder order) {
        uint64 orderMaturity = market.config().maturity;
        if (orderMaturity > block.timestamp + maxTerm) revert MarketIsLaterThanMaxTerm();

        if (
            supplyQueue.length + 1 >= VaultConstants.MAX_QUEUE_LENGTH ||
            withdrawQueue.length + 1 >= VaultConstants.MAX_QUEUE_LENGTH
        ) revert MaxQueueLengthExceeded();
        address assetAddress = asset();
        (IERC20 ft, IERC20 xt, , , IERC20 debtToken) = market.tokens();
        if (assetAddress != address(debtToken)) revert InconsistentAsset();

        order = market.createOrder(address(this), maxXtReserve, ISwapCallback(address(this)), curveCuts);
        if (initialReserve > 0) {
            IERC20(assetAddress).safeIncreaseAllowance(address(market), initialReserve);
            market.mint(address(order), initialReserve);
        }
        supplyQueue.push(address(order));
        withdrawQueue.push(address(order));
        orderMapping[address(order)] = OrderInfo({
            market: market,
            ft: ft,
            xt: xt,
            maxSupply: maxSupply.toUint128(),
            ftReserve: initialReserve.toUint128(),
            maturity: orderMaturity
        });

        emit CreateOrder(
            msg.sender,
            address(market),
            address(order),
            maxXtReserve,
            maxSupply,
            initialReserve,
            curveCuts
        );
    }

    function _setOrderMaxSupply(address order, uint256 maxSupply) internal {
        orderMapping[order].maxSupply = maxSupply.toUint128();
    }

    /// @notice Update order curve cuts and reserves
    function _updateOrder(
        ITermMaxOrder order,
        int256 changes,
        uint256 maxSupply,
        uint256 maxXtReserve,
        CurveCuts memory curveCuts
    ) internal {
        _checkOrder(address(order));
        OrderInfo memory orderInfo = orderMapping[address(order)];
        orderInfo.maxSupply = maxSupply.toUint128();
        OrderConfig memory newOrderConfig;
        newOrderConfig.curveCuts = curveCuts;
        newOrderConfig.maxXtReserve = maxXtReserve.toUint128();
        newOrderConfig.swapTrigger = ISwapCallback(address(this));
        if (changes < 0) {
            // withdraw assets from order and burn to assets
            order.updateOrder(newOrderConfig, changes, changes);
            uint withdrawChanges = (-changes).toUint256();
            orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), withdrawChanges);
            orderInfo.xt.safeIncreaseAllowance(address(orderInfo.market), withdrawChanges);
            orderInfo.market.burn(address(this), withdrawChanges);

            orderInfo.ftReserve -= withdrawChanges.toUint128();
        } else {
            // deposit assets to order
            uint depositChanges = changes.toUint256();
            IERC20(asset()).safeIncreaseAllowance(address(orderInfo.market), depositChanges);
            orderInfo.market.mint(address(order), depositChanges);

            orderInfo.ftReserve += depositChanges.toUint128();
            changes = 0;

            order.updateOrder(newOrderConfig, changes, changes);
        }
        orderMapping[address(order)] = orderInfo;

        emit UpdateOrder(msg.sender, address(order), changes, maxSupply, maxXtReserve, curveCuts);
    }

    function _depositAssets(uint256 amount) internal {
        uint amountLeft = amount;
        for (uint i = 0; i < supplyQueue.length; ++i) {
            address order = supplyQueue[i];

            //check maturity
            OrderInfo memory orderInfo = orderMapping[order];
            if (block.timestamp > orderInfo.maturity) continue;

            //check supply
            uint xtReserve = orderInfo.xt.balanceOf(order);
            if (xtReserve >= orderInfo.maxSupply) continue;

            uint depositAmt = (orderInfo.maxSupply - xtReserve).min(amountLeft);

            IERC20(asset()).safeIncreaseAllowance(address(orderInfo.market), depositAmt);
            orderInfo.market.mint(order, depositAmt);
            amountLeft -= depositAmt;
            if (amountLeft == 0) break;
            // update order ft reserve
            orderInfo.ftReserve += depositAmt.toUint128();
            orderMapping[order] = orderInfo;
        }
        // deposit to lpers
        totalFt += amount;
        lpersFt += amount;
    }

    function _withdrawAssets(address recipient, uint256 amount) internal {
        uint amountLeft = amount;
        uint assetBalance = IERC20(asset()).balanceOf(address(this));
        if (assetBalance >= amount) {
            IERC20(asset()).safeTransfer(recipient, amount);
            totalFt -= amount;
            lpersFt -= amount;
        } else {
            amountLeft -= assetBalance;
            uint length = withdrawQueue.length;
            // withdraw from orders
            for (uint i = 0; i < length; ++i) {
                address order = withdrawQueue[i];
                OrderInfo memory orderInfo = orderMapping[order];
                if (block.timestamp > orderInfo.maturity + Constants.LIQUIDATION_WINDOW) {
                    // redeem assets from expired order
                    uint256 totalRedeem = _redeemFromMarket(order, orderInfo);
                    length--;
                    i--;
                    if (totalRedeem < amountLeft) {
                        amountLeft -= totalRedeem;
                        continue;
                    } else {
                        IERC20(asset()).safeTransfer(recipient, amountLeft);
                        break;
                    }
                } else if (block.timestamp < orderInfo.maturity) {
                    // withraw ft and xt from order to burn
                    uint maxWithdraw = orderInfo.xt.balanceOf(order).min(orderInfo.ftReserve);
                    if (maxWithdraw < amountLeft) {
                        amountLeft -= maxWithdraw;
                        _burnFromOrder(ITermMaxOrder(order), orderInfo, maxWithdraw);
                        orderInfo.ftReserve -= maxWithdraw.toUint128();
                        orderMapping[order] = orderInfo;
                        continue;
                    } else {
                        _burnFromOrder(ITermMaxOrder(order), orderInfo, amountLeft);
                        orderInfo.ftReserve -= amountLeft.toUint128();
                        orderMapping[order] = orderInfo;
                        IERC20(asset()).safeTransfer(recipient, amount);
                        break;
                    }
                } else {
                    // ignore orders that are in liquidation window
                    continue;
                }
            }
            if (amountLeft > 0) {
                uint maxWithdraw = amount - amountLeft;
                revert InsufficientFunds(maxWithdraw, amount);
            }
        }

        totalFt -= amount;
        lpersFt -= amount;
    }

    function _withdrawIncentive(address recipient, uint256 amount) internal {
        if (amount > curatorIncentive) revert InsufficientFunds(curatorIncentive, amount);
        IERC20(asset()).safeTransfer(recipient, amount);
        curatorIncentive -= amount;
        totalFt -= amount;

        emit WithdrawIncentive(msg.sender, recipient, amount);
    }

    function _dealBadDebt(address recipient, address collaretal, uint256 amount) internal {
        uint badDebtAmt = badDebtMapping[collaretal];
        if (badDebtAmt == 0) revert NoBadDebt(collaretal);
        if (amount > badDebtAmt) revert InsufficientFunds(badDebtAmt, amount);
        uint collateralBalance = IERC20(collaretal).balanceOf(address(this));
        uint collateralOut = (amount * collateralBalance) / badDebtAmt;
        IERC20(collaretal).safeTransfer(recipient, collateralOut);
        badDebtMapping[collaretal] -= amount;
    }

    function _burnFromOrder(ITermMaxOrder order, OrderInfo memory orderInfo, uint256 amount) internal {
        order.withdrawAssets(orderInfo.ft, address(this), amount);
        order.withdrawAssets(orderInfo.xt, address(this), amount);
        orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), amount);
        orderInfo.xt.safeIncreaseAllowance(address(orderInfo.market), amount);
        orderInfo.market.burn(address(this), amount);
    }

    /// @notice Return the length of the supply queue
    function supplyQueueLength() external view returns (uint256) {
        return supplyQueue.length;
    }

    /// @notice Return the length of the withdraw queue
    function withdrawQueueLength() external view returns (uint256) {
        return withdrawQueue.length;
    }

    function _updateWithdrawQueue(uint256[] memory indexes) internal {
        uint length = withdrawQueue.length;
        if (indexes.length != length) {
            revert WithdrawQueueLengthMismatch();
        }
        bool[] memory seen = new bool[](length);
        address[] memory newWithdrawQueue = new address[](length);

        for (uint256 i; i < length; ++i) {
            uint256 prevIndex = indexes[i];

            // If prevIndex >= currLength, it will revert with native "Index out of bounds".
            address order = withdrawQueue[prevIndex];
            if (seen[prevIndex]) revert DuplicateOrder(order);
            seen[prevIndex] = true;

            newWithdrawQueue[i] = order;
        }
        withdrawQueue = newWithdrawQueue;

        emit UpdateWithdrawQueue(msg.sender, newWithdrawQueue);
    }

    function _updateSupplyQueue(uint256[] memory indexes) internal {
        uint length = supplyQueue.length;
        if (indexes.length != length) {
            revert SupplyQueueLengthMismatch();
        }
        bool[] memory seen = new bool[](length);
        address[] memory newSupplyQueue = new address[](length);

        for (uint256 i; i < length; ++i) {
            uint256 prevIndex = indexes[i];

            // If prevIndex >= currLength, it will revert with native "Index out of bounds".
            address order = supplyQueue[prevIndex];
            if (seen[prevIndex]) revert DuplicateOrder(order);
            seen[prevIndex] = true;

            newSupplyQueue[i] = order;
        }
        supplyQueue = newSupplyQueue;

        emit UpdateSupplyQueue(msg.sender, newSupplyQueue);
    }

    function _redeemFromMarket(address order, OrderInfo memory orderInfo) internal returns (uint256 totalRedeem) {
        ITermMaxOrder(order).withdrawAssets(orderInfo.ft, address(this), orderInfo.ftReserve);
        orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), orderInfo.ftReserve);

        IERC20 assetToken = IERC20(asset());
        uint totalAsset = assetToken.balanceOf(address(this));
        orderInfo.market.redeem(orderInfo.ftReserve, address(this));
        totalRedeem = assetToken.balanceOf(address(this)) - totalAsset;

        if (totalRedeem < orderInfo.ftReserve) {
            // storage bad debt
            (, , , address collateral, ) = orderInfo.market.tokens();
            badDebtMapping[collateral] = orderInfo.ftReserve - totalRedeem;
        }
        emit RedeemOrder(msg.sender, order, orderInfo.ftReserve, totalRedeem.toUint128());

        delete orderMapping[order];
        supplyQueue.remove(supplyQueue.indexOf(order));
        withdrawQueue.remove(withdrawQueue.indexOf(order));
    }
    /// @notice Calculate and distribute accrued interest
    function _accruedInterest() internal {
        uint256 interest = totalFt - lpersFt - curatorIncentive;
        uint256 deltaTime = block.timestamp - lastUpdateTime;
        interest = (interest * deltaTime) / _daysToMaturity();
        uint incentiveToCurator = (interest * curatorPercentage) / Constants.DECIMAL_BASE;
        curatorIncentive += incentiveToCurator;
        lpersFt += (interest - incentiveToCurator);
        lastUpdateTime = block.timestamp.toUint64();
    }

    function _checkLockedFt() internal view {
        if (lpersFt + curatorIncentive > totalFt) revert LockedFtGreaterThanTotalFt();
    }

    function _checkOrder(address orderAddress) internal view {
        if (address(orderMapping[orderAddress].market) == address(0)) {
            revert UnauthorizedOrder(orderAddress);
        }
    }

    function swapCallback(uint256 ftReserve) external override {
        address orderAddress = msg.sender;
        _checkOrder(orderAddress);
        OrderInfo memory orderInfo = orderMapping[orderAddress];
        _accruedInterest();

        totalFt = totalFt - orderInfo.ftReserve + ftReserve;
        _checkLockedFt();
        orderInfo.ftReserve = ftReserve.toUint128();
        orderMapping[orderAddress] = orderInfo;
    }
}
