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
import {ITermMaxVault} from "./ITermMaxVault.sol";

import {console} from "forge-std/console.sol";

abstract contract BaseVault is VaultErrors, VaultEvents, ISwapCallback, ITermMaxVault {
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
        uint64 maturity;
    }

    uint256 public totalFt;
    // locked ft = accretingPrincipal + performanceFee;
    uint256 public accretingPrincipal;
    uint256 public performanceFee;
    uint256 public annualizedInterest;

    uint64 public maxTerm;
    uint64 public performanceFeeRate;

    address[] public supplyQueue;
    mapping(address => OrderInfo) public orderMapping;
    mapping(address => uint256) public badDebtMapping;

    address[] public withdrawQueue;

    uint64 lastUpdateTime;

    uint64 public recentestMaturity;
    mapping(uint64 => uint64) private maturityMapping;
    mapping(uint64 => address[]) private maturityToOrders;
    mapping(uint64 => uint128) private maturityToInterest;

    constructor(uint64 maxTerm_, uint64 performanceFeeRate_) {
        if (maxTerm_ > VaultConstants.MAX_TERM) revert MaxTermExceeded();
        _setPerformanceFeeRate(performanceFeeRate_);
        maxTerm = maxTerm_;
    }

    function _setPerformanceFeeRate(uint64 newPerformanceFeeRate) internal {
        if (newPerformanceFeeRate > VaultConstants.MAX_PERFORMANCE_FEE_RATE) revert PerformanceFeeRateExceeded();
        performanceFeeRate = newPerformanceFeeRate;
    }

    function asset() public view virtual returns (address);

    function apr() public view override returns (uint256) {
        return (annualizedInterest * Constants.DECIMAL_BASE) / (accretingPrincipal + performanceFee);
    }

    function createOrder(
        ITermMaxMarket market,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external virtual returns (ITermMaxOrder order);

    function updateOrders(
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        CurveCuts[] memory curveCuts
    ) external virtual;

    function updateSupplyQueue(uint256[] memory indexes) external virtual;

    function updateWithdrawQueue(uint256[] memory indexes) external virtual;

    function redeemOrder(ITermMaxOrder order) external virtual;

    function withdrawPerformanceFee(address recipient, uint256 amount) external virtual;

    function _createOrder(
        ITermMaxMarket market,
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

        order = market.createOrder(address(this), maxSupply, ISwapCallback(address(this)), curveCuts);
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
            maturity: orderMaturity
        });
        _insertMaturity(orderMaturity);

        emit CreateOrder(msg.sender, address(market), address(order), maxSupply, initialReserve, curveCuts);
    }

    function _insertMaturity(uint64 maturity) internal {
        uint64 priorMaturity = recentestMaturity;
        if (recentestMaturity == 0) {
            recentestMaturity = maturity;
            return;
        } else if (maturity < priorMaturity) {
            recentestMaturity = maturity;
            maturityMapping[maturity] = priorMaturity;
            return;
        }

        uint64 nextMaturity = maturityMapping[priorMaturity];
        while (nextMaturity > 0) {
            if (maturity < nextMaturity) {
                maturityMapping[maturity] = nextMaturity;
                if (priorMaturity > 0) maturityMapping[priorMaturity] = maturity;
                return;
            } else if (maturity == nextMaturity) {
                break;
            } else {
                priorMaturity = nextMaturity;
                nextMaturity = maturityMapping[priorMaturity];
            }
        }
        maturityMapping[priorMaturity] = maturity;
    }

    /// @notice Update order curve cuts and reserves
    function _updateOrder(ITermMaxOrder order, int256 changes, uint256 maxSupply, CurveCuts memory curveCuts) internal {
        _checkOrder(address(order));
        OrderInfo memory orderInfo = orderMapping[address(order)];
        orderInfo.maxSupply = maxSupply.toUint128();
        OrderConfig memory newOrderConfig;
        newOrderConfig.curveCuts = curveCuts;
        newOrderConfig.maxXtReserve = maxSupply;
        newOrderConfig.swapTrigger = ISwapCallback(address(this));
        if (changes < 0) {
            // withdraw assets from order and burn to assets
            order.updateOrder(newOrderConfig, changes, changes);
            uint withdrawChanges = (-changes).toUint256();
            orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), withdrawChanges);
            orderInfo.xt.safeIncreaseAllowance(address(orderInfo.market), withdrawChanges);
            orderInfo.market.burn(address(this), withdrawChanges);
        } else {
            // deposit assets to order
            uint depositChanges = changes.toUint256();
            IERC20(asset()).safeIncreaseAllowance(address(orderInfo.market), depositChanges);
            orderInfo.market.mint(address(order), depositChanges);
            changes = 0;

            order.updateOrder(newOrderConfig, changes, changes);
        }
        orderMapping[address(order)] = orderInfo;
        emit UpdateOrder(msg.sender, address(order), changes, maxSupply, curveCuts);
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
        }
        // deposit to lpers
        totalFt += amount;
        accretingPrincipal += amount;
    }

    function _withdrawAssets(address recipient, uint256 amount) internal {
        uint amountLeft = amount;
        uint assetBalance = IERC20(asset()).balanceOf(address(this));
        if (assetBalance >= amount) {
            IERC20(asset()).safeTransfer(recipient, amount);
            totalFt -= amount;
            accretingPrincipal -= amount;
        } else {
            amountLeft -= assetBalance;
            uint length = withdrawQueue.length;
            // withdraw from orders
            uint i;
            while (length > 0 && i < length) {
                address order = withdrawQueue[i];
                OrderInfo memory orderInfo = orderMapping[order];
                if (block.timestamp > orderInfo.maturity + Constants.LIQUIDATION_WINDOW) {
                    // redeem assets from expired order
                    uint256 totalRedeem = _redeemFromMarket(order, orderInfo);
                    length--;
                    if (totalRedeem < amountLeft) {
                        amountLeft -= totalRedeem;
                        continue;
                    } else {
                        IERC20(asset()).safeTransfer(recipient, amountLeft);
                        amountLeft = 0;
                        break;
                    }
                } else if (block.timestamp < orderInfo.maturity) {
                    // withraw ft and xt from order to burn
                    uint maxWithdraw = orderInfo.xt.balanceOf(order).min(orderInfo.ft.balanceOf(order));

                    if (maxWithdraw < amountLeft) {
                        amountLeft -= maxWithdraw;
                        _burnFromOrder(ITermMaxOrder(order), orderInfo, maxWithdraw);
                        ++i;
                    } else {
                        _burnFromOrder(ITermMaxOrder(order), orderInfo, amountLeft);
                        IERC20(asset()).safeTransfer(recipient, amount);
                        amountLeft = 0;
                        break;
                    }
                } else {
                    // ignore orders that are in liquidation window
                    ++i;
                }
            }
            if (amountLeft > 0) {
                uint maxWithdraw = amount - amountLeft;
                revert InsufficientFunds(maxWithdraw, amount);
            }
        }

        totalFt -= amount;
        accretingPrincipal -= amount;
    }

    function _withdrawPerformanceFee(address recipient, uint256 amount) internal {
        if (amount > performanceFee) revert InsufficientFunds(performanceFee, amount);
        IERC20(asset()).safeTransfer(recipient, amount);
        performanceFee -= amount;
        totalFt -= amount;

        emit WithdrawPerformanceFee(msg.sender, recipient, amount);
    }

    function _dealBadDebt(
        address recipient,
        address collaretal,
        uint256 amount
    ) internal returns (uint256 collateralOut) {
        uint badDebtAmt = badDebtMapping[collaretal];
        if (badDebtAmt == 0) revert NoBadDebt(collaretal);
        if (amount > badDebtAmt) revert InsufficientFunds(badDebtAmt, amount);
        uint collateralBalance = IERC20(collaretal).balanceOf(address(this));
        collateralOut = (amount * collateralBalance) / badDebtAmt;
        IERC20(collaretal).safeTransfer(recipient, collateralOut);
        badDebtMapping[collaretal] -= amount;
        accretingPrincipal -= amount;
        totalFt -= amount;
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
        uint ftReserve = orderInfo.ft.balanceOf(order);
        ITermMaxOrder(order).withdrawAssets(orderInfo.ft, address(this), ftReserve);
        orderInfo.ft.safeIncreaseAllowance(address(orderInfo.market), ftReserve);
        totalRedeem = orderInfo.market.redeem(ftReserve, address(this));
        if (totalRedeem < ftReserve) {
            // storage bad debt
            (, , , address collateral, ) = orderInfo.market.tokens();
            badDebtMapping[collateral] = ftReserve - totalRedeem;
        }
        emit RedeemOrder(msg.sender, order, ftReserve.toUint128(), totalRedeem.toUint128());

        delete orderMapping[order];
        supplyQueue.remove(supplyQueue.indexOf(order));
        withdrawQueue.remove(withdrawQueue.indexOf(order));
    }

    /// @notice Calculate and distribute accrued interest
    function _accruedPeriodInterest(uint startTime, uint endTime) internal {
        uint interest = (annualizedInterest * (endTime - startTime)) / 365 days;
        uint performanceFeeToCurator = (interest * performanceFeeRate) / Constants.DECIMAL_BASE;
        // accrue interest
        performanceFee += performanceFeeToCurator;
        accretingPrincipal += (interest - performanceFeeToCurator);
    }

    function _accruedInterest() internal {
        uint64 now = block.timestamp.toUint64();

        uint lastTime = lastUpdateTime;
        uint64 recentMaturity = recentestMaturity;
        if (lastTime == 0) {
            lastTime = now;
        }
        while (now >= recentMaturity && recentMaturity != 0) {
            _accruedPeriodInterest(lastTime, recentMaturity);
            lastTime = recentMaturity;
            uint64 nextMaturity = maturityMapping[recentMaturity];
            delete maturityMapping[recentMaturity];
            // update anualized interest
            annualizedInterest -= maturityToInterest[recentMaturity];
            delete maturityToInterest[recentMaturity];
            recentMaturity = nextMaturity;
        }
        if (recentMaturity > 0) {
            _accruedPeriodInterest(lastTime, now);
            recentestMaturity = recentMaturity;
        } else {
            // all orders are expired
            recentestMaturity = 0;
            annualizedInterest = 0;
        }
        lastUpdateTime = now;
    }

    function _previewAccruedInterest() internal view returns (uint256 previewPrincipal, uint256 previewPerformanceFee) {
        uint64 now = block.timestamp.toUint64();

        uint lastTime = lastUpdateTime;
        if (lastTime == 0) {
            return (0, 0);
        }
        uint64 recentMaturity = recentestMaturity;
        uint previewAnualizedInterest = annualizedInterest;
        previewPrincipal = accretingPrincipal;
        previewPerformanceFee = performanceFee;

        while (now >= recentMaturity && recentMaturity != 0) {
            (uint256 previewInterest, uint256 previewPerformanceFeeToCurator) = _previewAccruedPeriodInterest(
                lastTime,
                recentMaturity,
                previewAnualizedInterest
            );
            lastTime = recentMaturity;
            uint64 nextMaturity = maturityMapping[recentMaturity];
            // update anualized interest
            previewAnualizedInterest -= maturityToInterest[recentMaturity];

            previewPerformanceFee += previewPerformanceFeeToCurator;
            previewPrincipal += previewInterest;

            recentMaturity = nextMaturity;
        }
        if (recentMaturity > 0) {
            (uint256 previewInterest, uint256 previewPerformanceFeeToCurator) = _previewAccruedPeriodInterest(
                lastTime,
                now,
                previewAnualizedInterest
            );
            previewPerformanceFee += previewPerformanceFeeToCurator;
            previewPrincipal += previewInterest;
        }
    }

    function _previewAccruedPeriodInterest(
        uint startTime,
        uint endTime,
        uint previewAnualizedInterest
    ) internal view returns (uint256, uint256) {
        uint interest = (previewAnualizedInterest * (endTime - startTime)) / 365 days;
        uint performanceFeeToCurator = (interest * performanceFeeRate) / Constants.DECIMAL_BASE;
        return (interest - performanceFeeToCurator, performanceFeeToCurator);
    }

    function _checkLockedFt() internal view {
        if (accretingPrincipal + performanceFee > totalFt) revert LockedFtGreaterThanTotalFt();
    }

    function _checkOrder(address orderAddress) internal view {
        if (address(orderMapping[orderAddress].market) == address(0)) {
            revert UnauthorizedOrder(orderAddress);
        }
    }

    function swapCallback(int256 deltaFt, int256) external override {
        address orderAddress = msg.sender;
        _checkOrder(orderAddress);
        uint64 maturity = orderMapping[orderAddress].maturity;
        _accruedInterest();
        uint ftChanges;

        if (deltaFt > 0) {
            ftChanges = deltaFt.toUint256();
            totalFt += ftChanges;
            uint deltaAnualizedInterest = (ftChanges * Constants.DAYS_IN_YEAR) / _daysToMaturity(maturity);

            maturityToInterest[maturity] += deltaAnualizedInterest.toUint128();

            annualizedInterest += deltaAnualizedInterest;
        } else {
            ftChanges = (-deltaFt).toUint256();
            totalFt -= ftChanges;
            uint deltaAnualizedInterest = (ftChanges * Constants.DAYS_IN_YEAR) / _daysToMaturity(maturity);
            if (maturityToInterest[maturity] < deltaAnualizedInterest || annualizedInterest < deltaAnualizedInterest) {
                revert LockedFtGreaterThanTotalFt();
            }
            maturityToInterest[maturity] -= deltaAnualizedInterest.toUint128();
            annualizedInterest -= deltaAnualizedInterest;
        }

        _checkLockedFt();
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity(uint256 maturity) internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }
}
