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

    function updateOrderCurves(address[] memory orders, CurveCuts[] memory curveCuts) external onlyProxy {
        require(orders.length == curveCuts.length, VaultErrorsV2.ArrayLengthMismatch());
        _accruedInterest();
        for (uint256 i = 0; i < orders.length; ++i) {
            address order = orders[i];
            _checkOrder(order);
            ITermMaxOrderV2(order).setCurve(curveCuts[i]);
        }
        emit VaultEventsV2.UpdateOrderCurve(msg.sender, orders);
    }

    function updateOrderPools(address[] memory orders, IERC4626[] memory pools) external onlyProxy {
        require(orders.length == pools.length, VaultErrorsV2.ArrayLengthMismatch());
        _accruedInterest();
        for (uint256 i = 0; i < orders.length; ++i) {
            address order = orders[i];
            _checkOrder(order);
            _checkPool(pools[i]);
            ITermMaxOrderV2(order).setPool(pools[i]);
        }
        emit VaultEventsV2.UpdateOrderPools(msg.sender, orders);
    }

    function _checkPool(IERC4626 pool) internal view {
        require(
            address(pool) == address(0) || _poolWhitelist[address(pool)],
            VaultErrorsV2.PoolNotWhitelisted(address(pool))
        );
    }

    function updateOrdersConfigAndLiquidity(
        IERC20 asset,
        address[] memory orders,
        OrderV2ConfigurationParams[] memory params
    ) external onlyProxy {
        require(orders.length == params.length, VaultErrorsV2.ArrayLengthMismatch());
        _accruedInterest();
        int256 totalChanges = 0;
        for (uint256 i = 0; i < orders.length; ++i) {
            address order = orders[i];
            OrderV2ConfigurationParams memory param = params[i];
            _checkOrder(order);
            ITermMaxOrderV2(order).setGeneralConfig(
                0, param.maxXtReserve, ISwapCallback(address(this)), param.virtualXtReserve
            );
            if (param.liquidityChanges > 0) {
                asset.safeIncreaseAllowance(order, uint256(param.liquidityChanges));
                ITermMaxOrderV2(order).addLiquidity(asset, uint256(param.liquidityChanges));
            } else if (param.liquidityChanges < 0) {
                ITermMaxOrderV2(order).removeLiquidity(asset, uint256(-param.liquidityChanges), address(this));
            }
            totalChanges += param.liquidityChanges;
        }
        /// @dev Check idle fund rate after all orders are updated if deposit funds to orders
        if (totalChanges > 0) {
            _checkIdleFundRate(asset);
        }
        emit VaultEventsV2.UpdateOrderCurve(msg.sender, orders);
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
        bytes memory deliveryData;
        (badDebt, deliveryData) = ITermMaxOrderV2(order).redeemAll(asset, address(this));
        if (badDebt != 0) {
            // store bad debt
            ITermMaxMarket market = ITermMaxOrder(order).market();
            (,,, address collateral, IERC20 debtToken) = market.tokens();
            _badDebtMapping[collateral] += badDebt;
            // That means the order use pool if the debt token is not the same as the asset
            if (debtToken != asset) {
                // transfer collateral to the vault
                deliveryCollateral = abi.decode(deliveryData, (uint256));
                ITermMaxOrder(order).withdrawAssets(IERC20(collateral), address(this), deliveryCollateral);
            }
        }
        delete _orderMaturityMapping[order];
        emit VaultEventsV2.RedeemOrder(msg.sender, order, badDebt, deliveryCollateral);
    }

    function createOrder(
        IERC20 asset,
        ITermMaxMarketV2 market,
        IERC4626 pool,
        OrderV2ConfigurationParams memory params,
        CurveCuts memory curveCuts
    ) external onlyProxy returns (ITermMaxOrderV2 order) {
        _accruedInterest();
        require(_marketWhitelist[address(market)], VaultErrorsV2.MarketNotWhitelisted(address(market)));

        _checkPool(pool);
        // (IERC20 ft, IERC20 xt,,, IERC20 debtToken) = market.tokens();
        OrderInitialParams memory initialParams;
        initialParams.virtualXtReserve = params.virtualXtReserve;
        initialParams.maker = address(this);
        initialParams.pool = pool;
        initialParams.orderConfig.maxXtReserve = params.maxXtReserve;
        initialParams.orderConfig.swapTrigger = ISwapCallback(address(this));
        initialParams.orderConfig.curveCuts = curveCuts;
        order = ITermMaxOrderV2(address(market.createOrder(initialParams)));
        if (params.liquidityChanges > 0) {
            // transfer asset to the order
            uint256 initialReserve = uint256(params.liquidityChanges);
            asset.safeIncreaseAllowance(address(order), initialReserve);
            ITermMaxOrderV2(address(order)).addLiquidity(asset, initialReserve);
            _checkIdleFundRate(asset);
        }
        uint64 orderMaturity = ITermMaxMarket(address(market)).config().maturity;
        _orderMaturityMapping[address(order)] = orderMaturity;
        _maturityMapping.insertWhenZeroAsRoot(orderMaturity);
        emit VaultEventsV2.NewOrderCreated(msg.sender, address(market), address(order));
    }

    function _checkIdleFundRate(IERC20 asset) internal view {
        uint256 __minIdleFundRate = _minIdleFundRate;
        if (__minIdleFundRate > 0) {
            uint256 idleFundBalance = asset.balanceOf(address(this));
            uint256 currentIdleFundRate = _accretingPrincipal == 0
                ? Constants.DECIMAL_BASE
                : (idleFundBalance * Constants.DECIMAL_BASE_SQ * Constants.DECIMAL_BASE) / _accretingPrincipal;

            if (currentIdleFundRate < __minIdleFundRate) {
                revert VaultErrorsV2.IdleFundRateTooLow(currentIdleFundRate, __minIdleFundRate);
            }
        }
    }

    function depositAssets(IERC20, uint256 amount) external onlyProxy {
        _accruedInterest();
        // deposit to lpers
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _totalFt += amplifiedAmt;
        _accretingPrincipal += amplifiedAmt;
    }

    function withdrawAssets(IERC20 asset, address recipient, uint256 amount) external onlyProxy {
        _accruedInterest();
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _totalFt -= amplifiedAmt;
        _accretingPrincipal -= amplifiedAmt;

        asset.safeTransfer(recipient, amount);
    }

    function _withdrawPerformanceFee(IERC20 asset, address recipient, uint256 amount) internal {
        uint256 amplifiedAmt = amount * Constants.DECIMAL_BASE_SQ;
        _performanceFee -= amplifiedAmt;
        _totalFt -= amplifiedAmt;

        asset.safeTransfer(recipient, amount);
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
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt) external onlyProxy {
        if (ftReserve < xtReserve) {
            revert VaultErrors.OrderHasNegativeInterest();
        }
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
        } else {
            ftChanges = uint256(-deltaFt) * Constants.DECIMAL_BASE_SQ;
            _totalFt -= ftChanges;
            uint256 deltaAnnualizedInterest = (ftChanges * 365 days) / (maturity - block.timestamp);
            uint256 maturityInterest = _maturityToInterest[maturity.toUint64()];
            if (maturityInterest < deltaAnnualizedInterest || _annualizedInterest < deltaAnnualizedInterest) {
                revert VaultErrors.LockedFtGreaterThanTotalFt();
            }
            _maturityToInterest[uint64(maturity)] = maturityInterest - deltaAnnualizedInterest;
            _annualizedInterest -= deltaAnnualizedInterest;
            _checkApy();
        }
        /// @dev Ensure that the total assets after the transaction are
        /// greater than or equal to the principal and the allocated interest
        _checkLockedFt();
    }
}
