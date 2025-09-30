// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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
import {ISwapCallback} from "../../v1/ISwapCallback.sol";
import {VaultStorageV2, OrderV2ConfigurationParams} from "./VaultStorageV2.sol";
import {VaultErrorsV2} from "../errors/VaultErrorsV2.sol";
import {VaultEventsV2} from "../events/VaultEventsV2.sol";
import {ITermMaxOrderV2} from "../ITermMaxOrderV2.sol";
import {ITermMaxMarketV2, OrderInitialParams} from "../ITermMaxMarketV2.sol";
import {OnlyProxyCall} from "../lib/OnlyProxyCall.sol";
import {IOrderManagerV2} from "./IOrderManagerV2.sol";

/**
 * @title Order Manager V2
 * @author Term Structure Labs
 * @notice The extension of the TermMaxVault that manages orders and calculates interest
 */
contract OrderManagerV2 is VaultStorageV2, OnlyProxyCall, IOrderManagerV2 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using ArrayUtils for address[];
    using MathLib for uint256;
    using LinkedList for mapping(uint64 => uint64);

    address private immutable ORDER_MANAGER_SINGLETON;

    constructor() {
        ORDER_MANAGER_SINGLETON = address(this);
    }

    function updateOrdersConfiguration(address[] memory orders, OrderV2ConfigurationParams[] memory orderConfigs)
        external
        onlyProxy
    {
        require(orders.length == orderConfigs.length, VaultErrorsV2.ArrayLengthMismatch());
        _accruedInterest();
        for (uint256 i = 0; i < orders.length; ++i) {
            address order = orders[i];
            OrderV2ConfigurationParams memory config = orderConfigs[i];
            _checkOrder(order);
            ITermMaxOrderV2(order).setCurveAndPrice(
                config.originalVirtualXtReserve, config.virtualXtReserve, config.maxXtReserve, config.curveCuts
            );
        }
        emit VaultEventsV2.OrdersConfigurationUpdated(msg.sender, orders);
    }

    function removeLiquidityFromOrders(IERC20 asset, address[] memory orders, uint256[] memory removedLiquidities)
        external
        onlyProxy
    {
        require(orders.length == removedLiquidities.length, VaultErrorsV2.ArrayLengthMismatch());
        _accruedInterest();
        uint256 totalRemovingLiquidity;
        for (uint256 i = 0; i < orders.length; ++i) {
            address order = orders[i];
            uint256 removingLiquidity = removedLiquidities[i];
            _checkOrder(order);
            if (removingLiquidity != 0) {
                ITermMaxOrderV2(order).removeLiquidity(asset, removingLiquidity, address(this));
                totalRemovingLiquidity += removingLiquidity;
            }
        }
        if (totalRemovingLiquidity != 0) {
            _depositToPoolOrNot(asset, totalRemovingLiquidity);
        }
        emit VaultEventsV2.OrdersLiquidityRemoved(msg.sender, orders, removedLiquidities);
    }

    function withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) external onlyProxy {
        _accruedInterest();
        _withdrawPerformanceFee(asset, recipient, amount);
    }

    function redeemOrder(IERC20 asset, address order)
        external
        onlyProxy
        returns (uint256 badDebt, uint256 deliveryCollateral)
    {
        _checkOrder(order);
        bytes memory deliveryData;
        (badDebt, deliveryData) = ITermMaxOrderV2(order).redeemAll(address(this));
        deliveryCollateral = deliveryData.length == 0 ? 0 : abi.decode(deliveryData, (uint256));
        if (badDebt != 0) {
            // store bad debt
            ITermMaxMarket market = ITermMaxOrder(order).market();
            (,,, address collateral,) = market.tokens();
            _badDebtMapping[collateral] += badDebt;
        }
        _depositToPoolOrNot(asset, asset.balanceOf(address(this)));

        delete _orderMaturityMapping[order];
        emit VaultEventsV2.RedeemOrder(msg.sender, order, badDebt, deliveryCollateral);
    }

    function createOrder(ITermMaxMarketV2 market, OrderV2ConfigurationParams memory params)
        external
        onlyProxy
        returns (ITermMaxOrderV2 order)
    {
        _accruedInterest();
        require(_marketWhitelist[address(market)], VaultErrorsV2.MarketNotWhitelisted(address(market)));

        // (IERC20 ft, IERC20 xt,,, IERC20 debtToken) = market.tokens();
        OrderInitialParams memory initialParams;
        initialParams.virtualXtReserve = params.virtualXtReserve;
        initialParams.maker = address(this);
        initialParams.orderConfig.maxXtReserve = params.maxXtReserve;
        initialParams.orderConfig.swapTrigger = ISwapCallback(address(this));
        initialParams.orderConfig.curveCuts = params.curveCuts;
        order = ITermMaxOrderV2(address(market.createOrder(initialParams)));
        uint64 orderMaturity = ITermMaxMarket(address(market)).config().maturity;
        _orderMaturityMapping[address(order)] = orderMaturity;
        _maturityMapping.insertWhenZeroAsRoot(orderMaturity);
        emit VaultEventsV2.NewOrderCreated(msg.sender, address(market), address(order));
    }

    function depositAssets(IERC20 asset, uint256 amount) external onlyProxy {
        _accruedInterest();
        // deposit to lpers
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _totalFt += amplifiedAmt;
        _accretingPrincipal += amplifiedAmt;
        _depositToPoolOrNot(asset, amount);
    }

    function withdrawAssets(IERC20 asset, address recipient, uint256 amount) external onlyProxy {
        _reduceAssets(amount);
        _withdrawFromPoolOrNot(asset, recipient, amount);
    }

    function withdrawFts(address order, uint256 amount, address recipient) external onlyProxy {
        _checkOrder(order);
        _reduceAssets(amount);

        ITermMaxMarket market = ITermMaxOrder(order).market();
        (IERC20 ft,,,,) = market.tokens();
        ITermMaxOrder(order).withdrawAssets(ft, recipient, amount);
    }

    function _reduceAssets(uint256 amount) internal {
        _accruedInterest();
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _totalFt -= amplifiedAmt;
        _accretingPrincipal -= amplifiedAmt;
    }

    function _depositToPoolOrNot(IERC20 asset, uint256 amount) internal {
        IERC4626 pool = _pool;
        if (pool != IERC4626(address(0))) {
            // deposit to the pool
            asset.safeIncreaseAllowance(address(pool), amount);
            pool.deposit(amount, address(this));
        }
    }

    function _withdrawFromPoolOrNot(IERC20 asset, address recipient, uint256 amount) internal {
        IERC4626 pool = _pool;
        if (pool != IERC4626(address(0))) {
            // withdraw from the pool
            pool.withdraw(amount, recipient, address(this));
        } else {
            // transfer asset to the recipient
            asset.safeTransfer(recipient, amount);
        }
    }

    function _withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) internal {
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _performanceFee -= amplifiedAmt;
        _totalFt -= amplifiedAmt;
        _withdrawFromPoolOrNot(asset, recipient, amount);
        emit VaultEvents.WithdrawPerformanceFee(msg.sender, recipient, amount);
    }

    function dealBadDebt(address recipient, address collateral, uint256 amount)
        external
        onlyProxy
        returns (uint256 collateralOut)
    {
        _accruedInterest();
        uint256 badDebtAmt = _badDebtMapping[collateral];
        require(badDebtAmt != 0, VaultErrors.NoBadDebt(collateral));
        require(amount <= badDebtAmt, VaultErrors.InsufficientFunds(badDebtAmt, amount));
        uint256 collateralBalance = IERC20(collateral).balanceOf(address(this));
        collateralOut = (amount * collateralBalance) / badDebtAmt;
        IERC20(collateral).safeTransfer(recipient, collateralOut);

        _badDebtMapping[collateral] -= amount;
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _accretingPrincipal -= amplifiedAmt;
        _totalFt -= amplifiedAmt;
    }

    /// @notice Calculate and distribute accrued the interest from start to end time
    function _accruedPeriodInterest(uint256 startTime, uint256 endTime) internal {
        uint256 interest = (_annualizedInterest * (endTime - startTime)) / 365 days;
        uint256 _performanceFeeToCurator = (interest * _performanceFeeRate) / Constants.DECIMAL_BASE;
        // accrue interest
        _performanceFee += _performanceFeeToCurator;
        _accretingPrincipal += (interest - _performanceFeeToCurator);
    }

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
        emit VaultEventsV2.AccruedInterest(_accretingPrincipal, _performanceFee);
        _lastUpdateTime = currentTime;
    }

    function _checkLockedFt() internal view {
        if (_accretingPrincipal + _performanceFee > _totalFt) revert VaultErrors.LockedFtGreaterThanTotalFt();
    }

    function _checkOrder(address orderAddress) internal view {
        require(_orderMaturityMapping[orderAddress] != 0, VaultErrors.UnauthorizedOrder(orderAddress));
    }

    function _checkApy() internal view {
        uint256 __minAPy = _minApy;
        if (__minAPy > 0) {
            uint256 currentApy = _accretingPrincipal == 0
                ? 0
                : (_annualizedInterest * (Constants.DECIMAL_BASE - _performanceFeeRate)) / (_accretingPrincipal);
            if (currentApy < __minAPy) {
                revert VaultErrorsV2.ApyTooLow(currentApy, __minAPy);
            }
        }
    }

    /// @notice Callback function for the swap
    /// @param deltaFt The change in the ft balance of the order
    function afterSwap(IERC20 asset, uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256 deltaXt)
        external
        onlyProxy
    {
        address orderAddress = msg.sender;
        /// @dev Check if the order is valid
        uint256 maturity = _orderMaturityMapping[orderAddress];
        require(maturity != 0, VaultErrors.UnauthorizedOrder(orderAddress));

        /// @dev Calculate interest from last update time to now
        _accruedInterest();

        /// @dev If ft increases, interest increases, and if ft decreases,
        ///  interest decreases. Update the expected annualized return based on the change
        uint256 ftChanges;

        if (deltaFt > 0) {
            ftChanges = uint256(deltaFt) * Constants.DECIMAL_BASE_SQ;
            _totalFt += ftChanges;
            uint256 deltaAnnualizedInterest = (ftChanges * 365 days) / (maturity - block.timestamp);

            _maturityToInterest[maturity.toUint64()] += deltaAnnualizedInterest;

            _annualizedInterest += deltaAnnualizedInterest;

            /// @dev release xt if needed
            int256 finalXtReserve = xtReserve.toInt256() + deltaXt;
            if (finalXtReserve < 0) {
                _releaseLiquidity(ITermMaxOrder(orderAddress), asset, uint256(-finalXtReserve));
            }
        } else {
            ftChanges = uint256(-deltaFt) * Constants.DECIMAL_BASE_SQ;
            _totalFt -= ftChanges;
            uint256 deltaAnnualizedInterest = (ftChanges * 365 days) / (maturity - block.timestamp);
            uint256 maturityInterest = _maturityToInterest[maturity.toUint64()];
            if (maturityInterest < deltaAnnualizedInterest || _annualizedInterest < deltaAnnualizedInterest) {
                revert VaultErrors.OrderHasNegativeInterest();
            }
            _maturityToInterest[uint64(maturity)] = maturityInterest - deltaAnnualizedInterest;
            _annualizedInterest -= deltaAnnualizedInterest;
            _checkApy();

            /// @dev Make sure that the interest of order does not go negative
            int256 finalFtReserve = ftReserve.toInt256() + deltaFt;
            int256 finalXtReserve = xtReserve.toInt256() + deltaXt;
            if (finalFtReserve < finalXtReserve) {
                revert VaultErrors.OrderHasNegativeInterest();
            }
        }
        /// @dev Ensure that the total assets after the transaction are
        /// greater than or equal to the principal and the allocated interest
        _checkLockedFt();
    }

    function _releaseLiquidity(ITermMaxOrder order, IERC20 asset, uint256 amount) internal {
        IERC4626 pool = _pool;
        if (pool != IERC4626(address(0))) {
            // withdraw from the pool
            pool.withdraw(amount, address(this), address(this));
        }

        ITermMaxMarket market = order.market();
        asset.safeIncreaseAllowance(address(market), amount);
        market.mint(address(order), amount);
    }
}
