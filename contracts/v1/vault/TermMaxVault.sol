// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    IERC4626,
    ERC4626Upgradeable,
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PendingLib, PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts, VaultInitialParams} from "../storage/TermMaxStorage.sol";
import {ITermMaxRouter} from "../router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {VaultConstants} from "../lib/VaultConstants.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";
import {ISwapCallback} from "../ISwapCallback.sol";
import {VaultErrors} from "../errors/VaultErrors.sol";
import {VaultEvents} from "../events/VaultEvents.sol";
import {IOrderManager} from "./IOrderManager.sol";
import {VaultStorage, OrderInfo} from "./VaultStorage.sol";
import {Constants} from "../lib/Constants.sol";
import {ITermMaxVault} from "./ITermMaxVault.sol";

contract TermMaxVault is
    VaultStorage,
    ITermMaxVault,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    VaultErrors,
    VaultEvents,
    ISwapCallback
{
    using SafeCast for uint256;
    using TransferUtils for IERC20;
    using PendingLib for *;

    address public immutable ORDER_MANAGER_SINGLETON;

    modifier onlyCuratorRole() {
        address sender = _msgSender();
        if (sender != _curator && sender != owner()) revert NotCuratorRole();
        _;
    }

    /// @dev Reverts if the caller doesn't have the guardian role.
    modifier onlyGuardianRole() {
        address sender = _msgSender();
        if (sender != _guardian && sender != owner()) revert NotGuardianRole();

        _;
    }

    /// @dev Reverts if the caller doesn't have the allocator role.
    modifier onlyAllocatorRole() {
        address sender = _msgSender();
        if (!_isAllocator[sender] && sender != _curator && sender != owner()) {
            revert NotAllocatorRole();
        }
        _;
    }

    modifier marketIsWhitelisted(address market) {
        if (_pendingMarkets[market].validAt != 0 && block.timestamp > _pendingMarkets[market].validAt) {
            _marketWhitelist[market] = true;
        }
        if (!_marketWhitelist[market]) revert MarketNotWhitelisted();
        _;
    }

    /// @dev Makes sure conditions are met to accept a pending value.
    /// @dev Reverts if:
    /// - there's no pending value;
    /// - the timelock has not elapsed since the pending value has been submitted.
    modifier afterTimelock(uint256 validAt) {
        if (validAt == 0) revert NoPendingValue();
        if (block.timestamp < validAt) revert TimelockNotElapsed();
        _;
    }

    constructor(address ORDER_MANAGER_SINGLETON_) {
        if (ORDER_MANAGER_SINGLETON_ == address(0)) revert InvalidImplementation();
        ORDER_MANAGER_SINGLETON = ORDER_MANAGER_SINGLETON_;
        _disableInitializers();
    }

    function initialize(VaultInitialParams memory params) external initializer {
        __ERC20_init(params.name, params.symbol);
        __Ownable_init(params.admin);
        __ERC4626_init(params.asset);
        __ReentrancyGuard_init();
        __Pausable_init();

        _setPerformanceFeeRate(params.performanceFeeRate);
        _checkTimelockBounds(params.timelock);
        _timelock = params.timelock;
        _maxCapacity = params.maxCapacity;
        _curator = params.curator;
    }

    function _setPerformanceFeeRate(uint64 newPerformanceFeeRate) internal {
        _delegateCall(abi.encodeCall(IOrderManager.accruedInterest, ()));
        _performanceFeeRate = newPerformanceFeeRate;
    }

    /// @notice View functions

    /**
     * @inheritdoc ITermMaxVault
     */
    function guardian() external view returns (address) {
        return _guardian;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function curator() external view returns (address) {
        return _curator;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function isAllocator(address allocator) external view returns (bool) {
        return _isAllocator[allocator];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function marketWhitelist(address market) external view returns (bool) {
        return _marketWhitelist[market];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function timelock() external view returns (uint256) {
        return _timelock;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingMarkets(address market) external view returns (PendingUint192 memory) {
        return _pendingMarkets[market];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingTimelock() external view returns (PendingUint192 memory) {
        return _pendingTimelock;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingPerformanceFeeRate() external view returns (PendingUint192 memory) {
        return _pendingPerformanceFeeRate;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingGuardian() external view returns (PendingAddress memory) {
        return _pendingGuardian;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function performanceFeeRate() external view returns (uint64) {
        return _performanceFeeRate;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function totalFt() external view returns (uint256) {
        return _totalFt / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function accretingPrincipal() external view returns (uint256) {
        (uint256 ap,) = _previewAccruedInterest();
        return ap / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function annualizedInterest() external view returns (uint256) {
        return _annualizedInterest / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function performanceFee() external view returns (uint256) {
        (, uint256 pf) = _previewAccruedInterest();
        return pf / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function supplyQueue(uint256 index) external view returns (address) {
        return _supplyQueue[index];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function withdrawQueue(uint256 index) external view returns (address) {
        return _withdrawQueue[index];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function orderMapping(address order) external view returns (OrderInfo memory) {
        return _orderMapping[order];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function badDebtMapping(address collateral) external view returns (uint256) {
        return _badDebtMapping[collateral];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function apr() external view returns (uint256) {
        if (_accretingPrincipal == 0) return 0;
        return (_annualizedInterest * (Constants.DECIMAL_BASE - _performanceFeeRate)) / (_accretingPrincipal);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function supplyQueueLength() external view returns (uint256) {
        return _supplyQueue.length;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function withdrawQueueLength() external view returns (uint256) {
        return _withdrawQueue.length;
    }

    // Ordermanager functions
    /**
     * @inheritdoc ITermMaxVault
     */
    function createOrder(ITermMaxMarket market, uint256 maxSupply, uint256 initialReserve, CurveCuts memory curveCuts)
        external
        onlyCuratorRole
        marketIsWhitelisted(address(market))
        whenNotPaused
        returns (ITermMaxOrder order)
    {
        order = abi.decode(
            _delegateCall(
                abi.encodeCall(
                    IOrderManager.createOrder, (IERC20(asset()), market, maxSupply, initialReserve, curveCuts)
                )
            ),
            (ITermMaxOrder)
        );
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function updateOrders(
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        CurveCuts[] memory curveCuts
    ) external onlyCuratorRole whenNotPaused {
        _delegateCall(
            abi.encodeCall(IOrderManager.updateOrders, (IERC20(asset()), orders, changes, maxSupplies, curveCuts))
        );
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function redeemOrder(ITermMaxOrder order) external onlyCuratorRole {
        _delegateCall(abi.encodeCall(IOrderManager.redeemOrder, (order)));
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function withdrawPerformanceFee(address recipient, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyCuratorRole
    {
        _delegateCall(abi.encodeCall(IOrderManager.withdrawPerformanceFee, (IERC20(asset()), recipient, amount)));
    }

    // ERC4626 functions

    /**
     * @dev See {IERC4626-maxDeposit}.
     */
    function maxDeposit(address) public view override(IERC4626, ERC4626Upgradeable) returns (uint256) {
        if (paused()) return 0;
        if (totalAssets() >= _maxCapacity) return 0;
        return _maxCapacity - totalAssets();
    }

    /**
     * @dev See {IERC4626-maxMint}.
     */
    function maxMint(address) public view override(IERC4626, ERC4626Upgradeable) returns (uint256) {
        if (paused()) return 0;
        return convertToShares(maxDeposit(address(0)));
    }

    /**
     * @dev Get total assets, falling back to real assets if virtual assets exceed limit
     */
    function totalAssets() public view override(IERC4626, ERC4626Upgradeable) returns (uint256) {
        (uint256 previewPrincipal,) = _previewAccruedInterest();
        return previewPrincipal / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address recipient, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
        whenNotPaused
    {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);

        _delegateCall(abi.encodeCall(IOrderManager.depositAssets, (IERC20(asset()), assets)));
        _mint(recipient, shares);

        emit Deposit(caller, recipient, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _delegateCall(abi.encodeCall(IOrderManager.withdrawAssets, (IERC20(asset()), receiver, assets)));
        _burn(owner, shares);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _delegateCall(bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = ORDER_MANAGER_SINGLETON.delegatecall(data);
        if (!success) {
            assembly {
                let ptr := add(returnData, 0x20)
                let len := mload(returnData)
                revert(ptr, len)
            }
        }
        return returnData;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function dealBadDebt(address collateral, uint256 badDebtAmt, address recipient, address owner)
        external
        nonReentrant
        returns (uint256 shares, uint256 collateralOut)
    {
        address caller = msg.sender;
        shares = previewWithdraw(badDebtAmt);
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(recipient, shares, maxShares);
        }

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        collateralOut = abi.decode(
            _delegateCall(abi.encodeCall(IOrderManager.dealBadDebt, (recipient, collateral, badDebtAmt))), (uint256)
        );

        emit DealBadDebt(caller, recipient, collateral, badDebtAmt, shares, collateralOut);
    }

    // Guardian functions
    function _setTimelock(uint256 newTimelock) internal {
        _timelock = newTimelock;

        emit SetTimelock(msg.sender, newTimelock);

        delete _pendingTimelock;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function submitTimelock(uint256 newTimelock) external onlyCuratorRole {
        if (newTimelock == _timelock) revert AlreadySet();
        if (_pendingTimelock.validAt != 0) revert AlreadyPending();
        _checkTimelockBounds(newTimelock);

        if (newTimelock > _timelock) {
            _setTimelock(newTimelock);
        } else {
            // Safe "unchecked" cast because newTimelock <= MAX_TIMELOCK.
            _pendingTimelock.update(uint184(newTimelock), _timelock);

            emit SubmitTimelock(newTimelock, _pendingTimelock.validAt);
        }
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function setCapacity(uint256 newCapacity) external onlyCuratorRole {
        if (newCapacity == _maxCapacity) revert AlreadySet();
        _maxCapacity = newCapacity;
        emit SetCapacity(_msgSender(), newCapacity);
    }

    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > VaultConstants.MAX_TIMELOCK) revert AboveMaxTimelock();
        if (newTimelock < VaultConstants.POST_INITIALIZATION_MIN_TIMELOCK) revert BelowMinTimelock();
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function submitPerformanceFeeRate(uint184 newPerformanceFeeRate) external onlyCuratorRole {
        if (newPerformanceFeeRate == _performanceFeeRate) revert AlreadySet();
        if (_pendingPerformanceFeeRate.validAt != 0) revert AlreadyPending();
        if (newPerformanceFeeRate > VaultConstants.MAX_PERFORMANCE_FEE_RATE) revert PerformanceFeeRateExceeded();
        if (newPerformanceFeeRate < _performanceFeeRate) {
            _setPerformanceFeeRate(uint256(newPerformanceFeeRate).toUint64());
            emit SetPerformanceFeeRate(_msgSender(), newPerformanceFeeRate);
            return;
        } else {
            _pendingPerformanceFeeRate.update(newPerformanceFeeRate, _timelock);
            emit SubmitPerformanceFeeRate(newPerformanceFeeRate, _pendingPerformanceFeeRate.validAt);
        }
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function submitGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == _guardian) revert AlreadySet();
        if (_pendingGuardian.validAt != 0) revert AlreadyPending();

        if (_guardian == address(0)) {
            _setGuardian(newGuardian);
        } else {
            _pendingGuardian.update(newGuardian, _timelock);
            emit SubmitGuardian(newGuardian, _pendingGuardian.validAt);
        }
    }

    /// @dev Sets `guardian` to `newGuardian`.
    function _setGuardian(address newGuardian) internal {
        _guardian = newGuardian;
        emit SetGuardian(_msgSender(), newGuardian);

        delete _pendingGuardian;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function submitMarket(address market, bool isWhitelisted) external onlyCuratorRole {
        if (_marketWhitelist[market] && isWhitelisted) revert AlreadySet();
        if (_pendingMarkets[market].validAt != 0) revert AlreadyPending();
        if (!isWhitelisted) {
            _setMarketWhitelist(market, isWhitelisted);
        } else {
            _pendingMarkets[market].update(0, _timelock);
            emit SubmitMarketToWhitelist(market, _pendingMarkets[market].validAt);
        }
    }

    function _setMarketWhitelist(address market, bool isWhitelisted) internal {
        _marketWhitelist[market] = isWhitelisted;
        emit SetMarketWhitelist(_msgSender(), market, isWhitelisted);
        delete _pendingMarkets[market];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function setIsAllocator(address newAllocator, bool newIsAllocator) external onlyOwner {
        if (_isAllocator[newAllocator] == newIsAllocator) revert AlreadySet();

        _isAllocator[newAllocator] = newIsAllocator;

        emit SetIsAllocator(newAllocator, newIsAllocator);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function setCurator(address newCurator) external onlyOwner {
        if (newCurator == _curator) revert AlreadySet();

        _curator = newCurator;

        emit SetCurator(newCurator);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function updateSupplyQueue(uint256[] memory indexes) external onlyAllocatorRole {
        _updateSupplyQueue(indexes);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function updateWithdrawQueue(uint256[] memory indexes) external onlyAllocatorRole {
        _updateWithdrawQueue(indexes);
    }

    function _updateWithdrawQueue(uint256[] memory indexes) internal {
        uint256 length = _withdrawQueue.length;
        if (indexes.length != length) {
            revert WithdrawQueueLengthMismatch();
        }
        bool[] memory seen = new bool[](length);
        address[] memory newWithdrawQueue = new address[](length);

        for (uint256 i; i < length; ++i) {
            uint256 prevIndex = indexes[i];

            // If prevIndex >= currLength, it will revert with native "Index out of bounds".
            address order = _withdrawQueue[prevIndex];
            if (seen[prevIndex]) revert DuplicateOrder(order);
            seen[prevIndex] = true;

            newWithdrawQueue[i] = order;
        }
        _withdrawQueue = newWithdrawQueue;

        emit UpdateWithdrawQueue(msg.sender, newWithdrawQueue);
    }

    function _updateSupplyQueue(uint256[] memory indexes) internal {
        uint256 length = _supplyQueue.length;
        if (indexes.length != length) {
            revert SupplyQueueLengthMismatch();
        }
        bool[] memory seen = new bool[](length);
        address[] memory newSupplyQueue = new address[](length);

        for (uint256 i; i < length; ++i) {
            uint256 prevIndex = indexes[i];

            // If prevIndex >= currLength, it will revert with native "Index out of bounds".
            address order = _supplyQueue[prevIndex];
            if (seen[prevIndex]) revert DuplicateOrder(order);
            seen[prevIndex] = true;

            newSupplyQueue[i] = order;
        }
        _supplyQueue = newSupplyQueue;

        emit UpdateSupplyQueue(msg.sender, newSupplyQueue);
    }

    /**
     * Revoke functions
     */

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingTimelock() external onlyGuardianRole {
        delete _pendingTimelock;

        emit RevokePendingTimelock(_msgSender());
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingGuardian() external onlyGuardianRole {
        delete _pendingGuardian;

        emit RevokePendingGuardian(_msgSender());
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingMarket(address market) external onlyGuardianRole {
        delete _pendingMarkets[market];

        emit RevokePendingMarket(_msgSender(), market);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingPerformanceFeeRate() external onlyGuardianRole {
        delete _pendingPerformanceFeeRate;

        emit RevokePendingPerformanceFeeRate(_msgSender());
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptTimelock() external afterTimelock(_pendingTimelock.validAt) {
        _setTimelock(_pendingTimelock.value);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptGuardian() external afterTimelock(_pendingGuardian.validAt) {
        _setGuardian(_pendingGuardian.value);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptMarket(address market) external afterTimelock(_pendingMarkets[market].validAt) {
        _setMarketWhitelist(market, true);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptPerformanceFeeRate() external afterTimelock(_pendingPerformanceFeeRate.validAt) {
        _setPerformanceFeeRate(uint256(_pendingPerformanceFeeRate.value).toUint64());
        delete _pendingPerformanceFeeRate;
        emit SetPerformanceFeeRate(_msgSender(), _performanceFeeRate);
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
        // pause orders
        for (uint256 i = 0; i < _supplyQueue.length; ++i) {
            ITermMaxOrder(_supplyQueue[i]).pause();
        }
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
        // unpause orders
        for (uint256 i = 0; i < _supplyQueue.length; ++i) {
            ITermMaxOrder(_supplyQueue[i]).unpause();
        }
    }

    function _previewAccruedInterest()
        internal
        view
        returns (uint256 previewPrincipal, uint256 previewPerformanceFee)
    {
        uint64 currentTime = block.timestamp.toUint64();

        uint256 lastTime = _lastUpdateTime;
        if (lastTime == 0) {
            return (_accretingPrincipal, _performanceFee);
        }
        uint64 recentMaturity = _maturityMapping[0];
        uint256 previewAnnualizedInterest = _annualizedInterest;
        previewPrincipal = _accretingPrincipal;
        previewPerformanceFee = _performanceFee;

        while (currentTime >= recentMaturity && recentMaturity != 0) {
            (uint256 previewInterest, uint256 previewPerformanceFeeToCurator) =
                _previewAccruedPeriodInterest(lastTime, recentMaturity, previewAnnualizedInterest);
            lastTime = recentMaturity;
            uint64 nextMaturity = _maturityMapping[recentMaturity];
            // update annualized interest
            previewAnnualizedInterest -= _maturityToInterest[recentMaturity];

            previewPerformanceFee += previewPerformanceFeeToCurator;
            previewPrincipal += previewInterest;

            recentMaturity = nextMaturity;
        }
        if (recentMaturity > 0) {
            (uint256 previewInterest, uint256 previewPerformanceFeeToCurator) =
                _previewAccruedPeriodInterest(lastTime, currentTime, previewAnnualizedInterest);
            previewPerformanceFee += previewPerformanceFeeToCurator;
            previewPrincipal += previewInterest;
        }
    }

    function _previewAccruedPeriodInterest(uint256 startTime, uint256 endTime, uint256 previewAnnualizedInterest)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 interest = (previewAnnualizedInterest * (endTime - startTime)) / 365 days;
        uint256 performanceFeeToCurator = (interest * _performanceFeeRate) / Constants.DECIMAL_BASE;
        return (interest - performanceFeeToCurator, performanceFeeToCurator);
    }

    /// @notice Callback function for the swap
    /// @param deltaFt The change in the ft balance of the order
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256) external override {
        _delegateCall(abi.encodeCall(IOrderManager.afterSwap, (ftReserve, xtReserve, deltaFt)));
    }
}
