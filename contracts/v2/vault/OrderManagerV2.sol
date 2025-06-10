// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {CurveCuts, OrderConfig} from "../../v1/storage/TermMaxStorage.sol";
import {VaultErrors} from "../../v1/errors/VaultErrors.sol";
import {VaultEvents} from "../../v1/events/VaultEvents.sol";
import {ITermMaxOrder} from "../../v1/ITermMaxOrder.sol";
import {TransferUtils} from "../../v1/lib/TransferUtils.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {ArrayUtils} from "../../v1/lib/ArrayUtils.sol";
import {MathLib} from "../../v1/lib/MathLib.sol";
import {LinkedList} from "../../v1/lib/LinkedList.sol";
import {IOrderManager} from "../../v1/vault/IOrderManager.sol";
import {ISwapCallback} from "../../v1/ISwapCallback.sol";
import {OrderInfo, VaultStorageV2} from "./VaultStorageV2.sol";
/**
 * @title Order Manager V2
 * @author Term Structure Labs
 * @notice The extension of the TermMaxVault that manages orders and calculates interest
 */

contract OrderManagerV2 is VaultStorageV2, VaultErrors, VaultEvents, IOrderManager {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using ArrayUtils for address[];
    using MathLib for uint256;
    using LinkedList for mapping(uint64 => uint64);

    address private immutable ORDER_MANAGER_SINGLETON;

    /**
     * @notice Reverts if the caller is not the proxy
     */
    modifier onlyProxy() {
        if (address(this) == ORDER_MANAGER_SINGLETON) revert OnlyProxy();
        _;
    }

    constructor() {
        ORDER_MANAGER_SINGLETON = address(this);
    }

    /**
     * @inheritdoc IOrderManager
     */
    function updateOrders(
        IERC20 asset,
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        CurveCuts[] memory curveCuts
    ) external override onlyProxy {
        _accruedInterest();
        for (uint256 i = 0; i < orders.length; ++i) {
            _updateOrder(asset, ITermMaxOrder(orders[i]), changes[i], maxSupplies[i], curveCuts[i]);
        }
    }

    /**
     * @inheritdoc IOrderManager
     */
    function withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) external override onlyProxy {
        _accruedInterest();
        _withdrawPerformanceFee(asset, recipient, amount);
    }

    /**
     * @inheritdoc IOrderManager
     */
    function redeemOrder(ITermMaxOrder order) external override onlyProxy {
        _redeemFromMarket(address(order), _orderMapping[address(order)]);
    }

    /**
     * @inheritdoc IOrderManager
     */
    function createOrder(
        IERC20 asset,
        ITermMaxMarket market,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external onlyProxy returns (ITermMaxOrder order) {
        (IERC20 ft, IERC20 xt,,, IERC20 debtToken) = market.tokens();
        if (asset != debtToken) revert InconsistentAsset();

        order = market.createOrder(address(this), maxSupply, ISwapCallback(address(this)), curveCuts);
        if (initialReserve > 0) {
            asset.safeIncreaseAllowance(address(market), initialReserve);
            market.mint(address(order), initialReserve);
        }

        uint64 orderMaturity = market.config().maturity;
        _orderMapping[address(order)] =
            OrderInfo({market: market, ft: ft, xt: xt, maxSupply: maxSupply.toUint128(), maturity: orderMaturity});
        _maturityMapping.insertWhenZeroAsRoot(orderMaturity);
        emit CreateOrder(msg.sender, address(market), address(order), maxSupply, initialReserve, curveCuts);
    }

    function _updateOrder(
        IERC20 asset,
        ITermMaxOrder order,
        int256 changes,
        uint256 maxSupply,
        CurveCuts memory curveCuts
    ) internal {
        _checkOrder(address(order));
        OrderInfo memory orderInfo = _orderMapping[address(order)];
        orderInfo.maxSupply = maxSupply.toUint128();
        OrderConfig memory newOrderConfig;
        newOrderConfig.curveCuts = curveCuts;
        newOrderConfig.maxXtReserve = maxSupply;
        newOrderConfig.swapTrigger = ISwapCallback(address(this));
        if (changes < 0) {
            // withdraw assets from order and burn to assets
            order.updateOrder(newOrderConfig, changes, changes);
            uint256 withdrawChanges = (-changes).toUint256();
            orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), withdrawChanges);
            orderInfo.xt.safeIncreaseAllowance(address(orderInfo.market), withdrawChanges);
            orderInfo.market.burn(address(this), withdrawChanges);
        } else {
            // deposit assets to order
            uint256 depositChanges = uint256(changes);
            asset.safeIncreaseAllowance(address(orderInfo.market), depositChanges);
            orderInfo.market.mint(address(order), depositChanges);
            // update curve cuts
            order.updateOrder(newOrderConfig, 0, 0);
        }
        _orderMapping[address(order)] = orderInfo;
        emit UpdateOrder(msg.sender, address(order), changes, maxSupply, curveCuts);
    }

    /**
     * @inheritdoc IOrderManager
     */
    function depositAssets(IERC20 asset, uint256 amount) external override onlyProxy {
        _accruedInterest();
        // deposit to lpers
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _totalFt += amplifiedAmt;
        _accretingPrincipal += amplifiedAmt;
    }

    /**
     * @inheritdoc IOrderManager
     */
    function withdrawAssets(IERC20 asset, address recipient, uint256 amount) external override onlyProxy {
        _accruedInterest();
        uint256 amountLeft = amount;
        uint256 assetBalance = asset.balanceOf(address(this));
        if (assetBalance >= amount) {
            asset.safeTransfer(recipient, amount);
        } else {
            revert InsufficientFunds(assetBalance, amount);
        }
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _totalFt -= amplifiedAmt;
        _accretingPrincipal -= amplifiedAmt;
    }

    function _withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) internal {
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        if (amplifiedAmt > _performanceFee) {
            revert InsufficientFunds(_performanceFee / Constants.DECIMAL_BASE_SQ, amount);
        }
        asset.safeTransfer(recipient, amount);
        _performanceFee -= amplifiedAmt;
        _totalFt -= amplifiedAmt;

        emit WithdrawPerformanceFee(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IOrderManager
     */
    function dealBadDebt(address recipient, address collateral, uint256 amount)
        external
        onlyProxy
        returns (uint256 collateralOut)
    {
        _accruedInterest();
        uint256 badDebtAmt = _badDebtMapping[collateral];
        if (badDebtAmt == 0) revert NoBadDebt(collateral);
        if (amount > badDebtAmt) revert InsufficientFunds(badDebtAmt, amount);
        uint256 collateralBalance = IERC20(collateral).balanceOf(address(this));
        collateralOut = (amount * collateralBalance) / badDebtAmt;
        IERC20(collateral).safeTransfer(recipient, collateralOut);

        _badDebtMapping[collateral] -= amount;
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _accretingPrincipal -= amplifiedAmt;
        _totalFt -= amplifiedAmt;
    }

    function _burnFromOrder(ITermMaxOrder order, OrderInfo memory orderInfo, uint256 amount) internal {
        order.withdrawAssets(orderInfo.ft, address(this), amount);
        order.withdrawAssets(orderInfo.xt, address(this), amount);
        orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), amount);
        orderInfo.xt.safeIncreaseAllowance(address(orderInfo.market), amount);

        orderInfo.market.burn(address(this), amount);
    }

    function _redeemFromMarket(address order, OrderInfo memory orderInfo) internal returns (uint256 totalRedeem) {
        uint256 ftReserve = orderInfo.ft.balanceOf(order);
        if (ftReserve != 0) {
            ITermMaxOrder(order).withdrawAssets(orderInfo.ft, address(this), ftReserve);
            orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), ftReserve);
            (totalRedeem,) = orderInfo.market.redeem(ftReserve, address(this));
            if (totalRedeem < ftReserve) {
                // storage bad debt
                (,,, address collateral,) = orderInfo.market.tokens();
                _badDebtMapping[collateral] += ftReserve - totalRedeem;
            }
        }
        emit RedeemOrder(msg.sender, order, ftReserve.toUint128(), totalRedeem.toUint128());

        delete _orderMapping[order];
    }

    /// @notice Calculate and distribute accrued the interest from start to end time
    function _accruedPeriodInterest(uint256 startTime, uint256 endTime) internal {
        uint256 interest = (_annualizedInterest * (endTime - startTime)) / 365 days;
        uint256 _performanceFeeToCurator = (interest * _performanceFeeRate) / Constants.DECIMAL_BASE;
        // accrue interest
        _performanceFee += _performanceFeeToCurator;
        _accretingPrincipal += (interest - _performanceFeeToCurator);
    }

    /**
     * @inheritdoc IOrderManager
     */
    function accruedInterest() external onlyProxy {
        _accruedInterest();
    }

    /// @notice Distribute interest
    function _accruedInterest() internal {
        uint64 currentTime = block.timestamp.toUint64();
        uint256 lastTime = _lastUpdateTime;
        if (currentTime == lastTime) return;
        uint64 recentMaturity = _maturityMapping[0];
        if (recentMaturity == 0) return;
        while (recentMaturity != 0 && recentMaturity <= currentTime) {
            // pop first maturity
            _maturityMapping.popWhenZeroAsRoot();
            _accruedPeriodInterest(lastTime, recentMaturity);
            // update last time
            lastTime = recentMaturity;
            // update annualized interest
            _annualizedInterest -= _maturityToInterest[recentMaturity];
            delete _maturityToInterest[recentMaturity];
            // get next maturity
            recentMaturity = _maturityMapping[0];
        }
        // accrued interest for the remaining maturity
        if (recentMaturity > 0) {
            _accruedPeriodInterest(lastTime, currentTime);
        } else {
            // all orders are expired
            _annualizedInterest = 0;
        }
        _lastUpdateTime = currentTime;
    }

    function _checkLockedFt() internal view {
        if (_accretingPrincipal + _performanceFee > _totalFt) revert LockedFtGreaterThanTotalFt();
    }

    function _checkOrder(address orderAddress) internal view {
        if (address(_orderMapping[orderAddress].market) == address(0)) {
            revert UnauthorizedOrder(orderAddress);
        }
    }

    /// @notice Callback function for the swap
    /// @param deltaFt The change in the ft balance of the order
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt) external onlyProxy {
        if (ftReserve < xtReserve) {
            revert OrderHasNegativeInterest();
        }
        address orderAddress = msg.sender;
        /// @dev Check if the order is valid
        _checkOrder(orderAddress);
        uint64 maturity = _orderMapping[orderAddress].maturity;
        /// @dev Calculate interest from last update time to now
        _accruedInterest();

        /// @dev If ft increases, interest increases, and if ft decreases,
        ///  interest decreases. Update the expected annualized return based on the change
        uint256 ftChanges;

        if (deltaFt > 0) {
            ftChanges = uint256(deltaFt) * Constants.DECIMAL_BASE_SQ;
            _totalFt += ftChanges;
            uint256 deltaAnnualizedInterest = ftChanges * 365 days / uint256(maturity - block.timestamp);

            _maturityToInterest[maturity] += deltaAnnualizedInterest;

            _annualizedInterest += deltaAnnualizedInterest;
        } else {
            ftChanges = uint256(-deltaFt) * Constants.DECIMAL_BASE_SQ;
            _totalFt -= ftChanges;
            uint256 deltaAnnualizedInterest = (ftChanges * 365 days) / uint256(maturity - block.timestamp);
            if (
                _maturityToInterest[maturity] < deltaAnnualizedInterest || _annualizedInterest < deltaAnnualizedInterest
            ) {
                revert LockedFtGreaterThanTotalFt();
            }
            _maturityToInterest[maturity] -= deltaAnnualizedInterest;
            _annualizedInterest -= deltaAnnualizedInterest;
        }
        /// @dev Ensure that the total assets after the transaction are
        ///greater than or equal to the principal and the allocated interest
        _checkLockedFt();
    }
}
