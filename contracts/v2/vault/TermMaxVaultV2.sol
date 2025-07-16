// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

/**
 * @title TermMaxVaultV2
 * @notice This contract is inspired by MetaMorphoV1_1 (https://github.com/morpho-org/metamorpho-v1.1/blob/main/src/MetaMorphoV1_1.sol)
 * @dev The role management structure is based on Morpho's role system (https://docs.morpho.org/curation/concepts/roles/)
 * with similar separation of curator, guardian, and allocator roles for enhanced governance and risk management.
 */
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
import {PendingLib, PendingAddress, PendingUint192} from "../../v1/lib/PendingLib.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {ITermMaxOrderV2} from "../ITermMaxOrderV2.sol";
import {VaultInitialParams, CurveCuts} from "../../v1/storage/TermMaxStorage.sol";
import {VaultInitialParamsV2} from "../storage/TermMaxStorageV2.sol";
import {ITermMaxOrder} from "../../v1/ITermMaxOrder.sol";
import {VaultConstants} from "../../v1/lib/VaultConstants.sol";
import {TransferUtils} from "../../v1/lib/TransferUtils.sol";
import {ISwapCallback} from "../../v1/ISwapCallback.sol";
import {VaultErrors} from "../../v1/errors/VaultErrors.sol";
import {VaultEvents} from "../../v1/events/VaultEvents.sol";
import {VaultEventsV2} from "../events/VaultEventsV2.sol";
import {IOrderManager} from "../../v1/vault/IOrderManager.sol";
import {IOrderManagerV2} from "./IOrderManagerV2.sol";
import {VaultStorageV2, OrderV2ConfigurationParams} from "./VaultStorageV2.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {ITermMaxVaultV2} from "./ITermMaxVaultV2.sol";
import {VaultErrorsV2} from "../errors/VaultErrorsV2.sol";
import {TransactionReentrancyGuard} from "../lib/TransactionReentrancyGuard.sol";
import {VersionV2} from "../VersionV2.sol";

contract TermMaxVaultV2 is
    VaultStorageV2,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    ISwapCallback,
    ITermMaxVaultV2,
    TransactionReentrancyGuard,
    VersionV2
{
    using SafeCast for uint256;
    using TransferUtils for IERC20;
    using PendingLib for *;

    address public immutable ORDER_MANAGER_SINGLETON;

    // keccak256(abi.encode(uint256(keccak256("termmax.tsstorage.vault.actionDeposit")) - 1)) & ~bytes32(uint256(0xff))
    uint256 private constant ACTION_DEPOSIT = 0x1d9ff85e70b948f53a2cc45fa6f42c020b2a8eec3349351855dea946b0635700;
    // keccak256(abi.encode(uint256(keccak256("termmax.tsstorage.vault.actionWithdraw")) - 1)) & ~bytes32(uint256(0xff))
    uint256 private constant ACTION_WITHDRAW = 0xfcb0c32c4f653382a412cb0caa6a29f9e46d74bae452ca200c67f1e5e6389300;

    modifier onlyCuratorRole() {
        address sender = _msgSender();
        if (sender != _curator && sender != owner()) revert VaultErrors.NotCuratorRole();
        _;
    }

    /// @dev Reverts if the caller doesn't have the guardian role.
    modifier onlyGuardianRole() {
        address sender = _msgSender();
        if (sender != _guardian && sender != owner()) revert VaultErrors.NotGuardianRole();

        _;
    }

    /// @dev Makes sure conditions are met to accept a pending value.
    /// @dev Reverts if:
    /// - there's no pending value;
    /// - the timelock has not elapsed since the pending value has been submitted.
    modifier afterTimelock(uint256 validAt) {
        if (validAt == 0) revert VaultErrors.NoPendingValue();
        if (block.timestamp < validAt) revert VaultErrors.TimelockNotElapsed();
        _;
    }

    constructor(address ORDER_MANAGER_SINGLETON_) {
        ORDER_MANAGER_SINGLETON = ORDER_MANAGER_SINGLETON_;
        _disableInitializers();
    }

    function initialize(VaultInitialParamsV2 memory params) external virtual initializer {
        __ERC20_init_unchained(params.name, params.symbol);
        __Ownable_init_unchained(params.admin);
        __ERC4626_init_unchained(params.asset);
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        _checkPerformanceFeeRateBounds(params.performanceFeeRate);
        _setPerformanceFeeRate(params.performanceFeeRate);
        _checkTimelockBounds(params.timelock);
        _setTimelock(params.timelock);
        _setMinApy(params.minApy);
        _setGuardian(params.guardian);
        _setCapacity(params.maxCapacity);
        _setCurator(params.curator);
        _setPool(address(params.pool));
    }

    function initialize(VaultInitialParams memory) external virtual initializer {
        revert VaultErrorsV2.UseVaultInitialParamsV2();
    }

    function _setPerformanceFeeRate(uint64 newPerformanceFeeRate) internal {
        _delegateCall(abi.encodeCall(IOrderManager.accruedInterest, ()));
        _performanceFeeRate = newPerformanceFeeRate;
        emit VaultEvents.SetPerformanceFeeRate(_msgSender(), newPerformanceFeeRate);
    }

    /// @notice View functions

    function guardian() external view virtual returns (address) {
        return _guardian;
    }

    function curator() external view virtual returns (address) {
        return _curator;
    }

    function marketWhitelist(address market) external view virtual returns (bool) {
        return _marketWhitelist[market];
    }

    function poolWhitelist(address pool) external view virtual returns (bool) {
        return _poolWhitelist[pool];
    }

    function timelock() external view virtual returns (uint256) {
        return _timelock;
    }

    function pendingMarkets(address market) external view virtual returns (PendingUint192 memory) {
        return _pendingMarkets[market];
    }

    function pendingPools() external view virtual returns (PendingAddress memory) {
        return _pendingPool;
    }

    function pendingTimelock() external view virtual returns (PendingUint192 memory) {
        return _pendingTimelock;
    }

    function pendingPerformanceFeeRate() external view virtual returns (PendingUint192 memory) {
        return _pendingPerformanceFeeRate;
    }

    function pendingGuardian() external view virtual returns (PendingAddress memory) {
        return _pendingGuardian;
    }

    function performanceFeeRate() external view virtual returns (uint64) {
        return _performanceFeeRate;
    }

    function totalFt() external view virtual returns (uint256) {
        return _totalFt / Constants.DECIMAL_BASE_SQ;
    }

    function accretingPrincipal() external view virtual returns (uint256) {
        (uint256 ap,) = _previewAccruedInterest();
        return ap / Constants.DECIMAL_BASE_SQ;
    }

    function annualizedInterest() external view virtual returns (uint256) {
        return _annualizedInterest / Constants.DECIMAL_BASE_SQ;
    }

    function performanceFee() external view virtual returns (uint256) {
        (, uint256 pf) = _previewAccruedInterest();
        return pf / Constants.DECIMAL_BASE_SQ;
    }

    function supplyQueue(uint256) external view virtual returns (address) {
        revert VaultErrorsV2.SupplyQueueNoLongerSupported();
    }

    function withdrawQueue(uint256) external view virtual returns (address) {
        revert VaultErrorsV2.WithdrawalQueueNoLongerSupported();
    }

    function orderMaturity(address order) external view virtual returns (uint256) {
        return _orderMaturityMapping[order];
    }

    function badDebtMapping(address collateral) external view virtual returns (uint256) {
        return _badDebtMapping[collateral];
    }

    function apr() external view virtual returns (uint256) {
        revert VaultErrorsV2.UseApyInsteadOfApr();
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function apy() external view virtual override returns (uint256) {
        uint256 accretingPrincipal_ = _accretingPrincipal;
        if (accretingPrincipal_ == 0) return 0;
        return (_annualizedInterest * (Constants.DECIMAL_BASE - _performanceFeeRate)) / (accretingPrincipal_);
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function minApy() external view virtual override returns (uint64) {
        return _minApy;
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function pendingMinApy() external view virtual override returns (PendingUint192 memory) {
        return _pendingMinApy;
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function submitPendingMinApy(uint64 newMinApy) external virtual override onlyCuratorRole {
        if (newMinApy == _minApy) revert VaultErrors.AlreadySet();
        if (_pendingMinApy.validAt != 0) revert VaultErrors.AlreadyPending();

        if (newMinApy > _minApy) {
            _setMinApy(newMinApy);
        } else {
            _pendingMinApy.update(uint184(newMinApy), _timelock);
            emit VaultEventsV2.SubmitMinApy(newMinApy, _pendingMinApy.validAt);
        }
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function acceptPendingMinApy() external virtual override afterTimelock(_pendingMinApy.validAt) {
        _setMinApy(uint64(_pendingMinApy.value));
        delete _pendingMinApy;
    }

    /// @dev Sets `_minApy` to `newMinApy`.
    function _setMinApy(uint64 newMinApy) internal {
        _minApy = newMinApy;
        emit VaultEventsV2.SetMinApy(_msgSender(), newMinApy);
    }

    // Ordermanager functions

    function createOrder(ITermMaxMarketV2 market, OrderV2ConfigurationParams memory params, CurveCuts memory curveCuts)
        external
        virtual
        nonReentrant
        onlyCuratorRole
        whenNotPaused
        returns (ITermMaxOrderV2 order)
    {
        order = abi.decode(
            _delegateCall(abi.encodeCall(IOrderManagerV2.createOrder, (IERC20(asset()), market, params, curveCuts))),
            (ITermMaxOrderV2)
        );
    }

    function updateOrders(
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        CurveCuts[] memory curveCuts
    ) external virtual nonReentrant onlyCuratorRole whenNotPaused {
        _delegateCall(
            abi.encodeCall(IOrderManager.updateOrders, (IERC20(asset()), orders, changes, maxSupplies, curveCuts))
        );
    }

    function updateOrderCurves(address[] memory orders, CurveCuts[] memory newCurveCuts)
        external
        virtual
        onlyCuratorRole
        whenNotPaused
    {
        _delegateCall(abi.encodeCall(IOrderManagerV2.updateOrderCurves, (orders, newCurveCuts)));
    }

    function updateOrdersConfigAndLiquidity(address[] memory orders, OrderV2ConfigurationParams[] memory params)
        external
        virtual
        nonReentrant
        onlyCuratorRole
        whenNotPaused
    {
        _delegateCall(abi.encodeCall(IOrderManagerV2.updateOrdersConfigAndLiquidity, (IERC20(asset()), orders, params)));
    }

    function redeemOrder(ITermMaxOrderV2 order)
        external
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 badDebt, uint256 deliveryCollateral)
    {
        bytes memory returnData =
            _delegateCall(abi.encodeCall(IOrderManagerV2.redeemOrder, (IERC20(asset()), address(order))));
        (badDebt, deliveryCollateral) = abi.decode(returnData, (uint256, uint256));
    }

    function withdrawPerformanceFee(address recipient, uint256 amount)
        external
        virtual
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
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;
        if (totalAssets() >= _maxCapacity) return 0;
        return _maxCapacity - totalAssets();
    }

    /**
     * @dev See {IERC4626-maxMint}.
     */
    function maxMint(address) public view override returns (uint256) {
        if (paused()) return 0;
        return convertToShares(maxDeposit(address(0)));
    }

    /**
     * @dev Get total assets, falling back to real assets if virtual assets exceed limit
     */
    function totalAssets() public view override returns (uint256) {
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
        nonTxReentrantBetweenActions(ACTION_DEPOSIT)
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
        nonTxReentrantBetweenActions(ACTION_WITHDRAW)
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

    function dealBadDebt(address collateral, uint256 badDebtAmt, address recipient, address owner)
        external
        virtual
        nonReentrant
        returns (uint256 shares, uint256 collateralOut)
    {
        if (collateral == asset()) revert VaultErrorsV2.CollateralIsAsset();
        address caller = msg.sender;
        shares = previewWithdraw(badDebtAmt);
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(recipient, shares, maxShares);
        }

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        collateralOut = abi.decode(
            _delegateCall(abi.encodeCall(IOrderManager.dealBadDebt, (recipient, collateral, badDebtAmt))), (uint256)
        );

        emit VaultEvents.DealBadDebt(caller, recipient, collateral, badDebtAmt, shares, collateralOut);
    }

    // Guardian functions
    function _setTimelock(uint256 newTimelock) internal {
        _timelock = newTimelock;

        emit VaultEvents.SetTimelock(msg.sender, newTimelock);

        delete _pendingTimelock;
    }

    function submitTimelock(uint256 newTimelock) external virtual onlyCuratorRole {
        if (newTimelock == _timelock) revert VaultErrors.AlreadySet();
        if (_pendingTimelock.validAt != 0) revert VaultErrors.AlreadyPending();
        _checkTimelockBounds(newTimelock);

        if (newTimelock > _timelock) {
            _setTimelock(newTimelock);
        } else {
            // Safe "unchecked" cast because newTimelock <= MAX_TIMELOCK.
            _pendingTimelock.update(uint184(newTimelock), _timelock);

            emit VaultEvents.SubmitTimelock(newTimelock, _pendingTimelock.validAt);
        }
    }

    function setCapacity(uint256 newCapacity) external virtual onlyCuratorRole {
        if (newCapacity == _maxCapacity) revert VaultErrors.AlreadySet();
        _setCapacity(newCapacity);
    }

    function _setCapacity(uint256 newCapacity) internal {
        _maxCapacity = newCapacity;
        emit VaultEvents.SetCapacity(_msgSender(), newCapacity);
    }

    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > VaultConstants.MAX_TIMELOCK) revert VaultErrors.AboveMaxTimelock();
        if (newTimelock < VaultConstants.POST_INITIALIZATION_MIN_TIMELOCK) revert VaultErrors.BelowMinTimelock();
    }

    function _checkPerformanceFeeRateBounds(uint256 newPerformanceFeeRate) internal pure {
        if (newPerformanceFeeRate > VaultConstants.MAX_PERFORMANCE_FEE_RATE) {
            revert VaultErrors.PerformanceFeeRateExceeded();
        }
    }

    function submitPerformanceFeeRate(uint184 newPerformanceFeeRate) external virtual onlyCuratorRole {
        if (newPerformanceFeeRate == _performanceFeeRate) revert VaultErrors.AlreadySet();
        if (_pendingPerformanceFeeRate.validAt != 0) revert VaultErrors.AlreadyPending();
        _checkPerformanceFeeRateBounds(newPerformanceFeeRate);
        if (newPerformanceFeeRate < _performanceFeeRate) {
            _setPerformanceFeeRate(uint256(newPerformanceFeeRate).toUint64());
            emit VaultEvents.SetPerformanceFeeRate(_msgSender(), newPerformanceFeeRate);
            return;
        } else {
            _pendingPerformanceFeeRate.update(newPerformanceFeeRate, _timelock);
            emit VaultEvents.SubmitPerformanceFeeRate(newPerformanceFeeRate, _pendingPerformanceFeeRate.validAt);
        }
    }

    function submitGuardian(address newGuardian) external virtual onlyOwner {
        if (newGuardian == _guardian) revert VaultErrors.AlreadySet();
        if (_pendingGuardian.validAt != 0) revert VaultErrors.AlreadyPending();

        if (_guardian == address(0)) {
            _setGuardian(newGuardian);
        } else {
            _pendingGuardian.update(newGuardian, _timelock);
            emit VaultEvents.SubmitGuardian(newGuardian, _pendingGuardian.validAt);
        }
    }

    /// @dev Sets `guardian` to `newGuardian`.
    function _setGuardian(address newGuardian) internal {
        _guardian = newGuardian;
        emit VaultEvents.SetGuardian(_msgSender(), newGuardian);

        delete _pendingGuardian;
    }

    function submitMarket(address market, bool isWhitelisted) external virtual onlyCuratorRole {
        if (!_submitPendingWhitelist(_marketWhitelist, _pendingMarkets, _setMarketWhitelist, market, isWhitelisted)) {
            emit VaultEvents.SubmitMarketToWhitelist(market, _pendingMarkets[market].validAt);
        }
    }

    function _setMarketWhitelist(address market, bool isWhitelisted) internal {
        _marketWhitelist[market] = isWhitelisted;
        emit VaultEvents.SetMarketWhitelist(_msgSender(), market, isWhitelisted);
        delete _pendingMarkets[market];
    }

    function submitPendingPool(address pool) external virtual onlyCuratorRole {
        if (pool == address(_pool)) revert VaultErrors.AlreadySet();
        if (_pendingPool.validAt != 0) revert VaultErrors.AlreadyPending();

        _pendingPool.update(pool, _timelock);

        emit VaultEventsV2.SubmitPendingPool(pool, _pendingPool.validAt);
    }

    function _setPool(address pool) internal {
        IERC4626 oldPool = _pool;
        if (oldPool != IERC4626(address(0))) {
            oldPool.redeem(oldPool.balanceOf(address(this)), address(this), address(this));
        }
        if (pool != address(0)) {
            IERC4626(pool).deposit(IERC20(asset()).balanceOf(address(this)), address(this));
        }
        _pool = IERC4626(pool);

        emit VaultEventsV2.SetPool(_msgSender(), pool);
        delete _pendingPool;
    }

    function _submitPendingWhitelist(
        mapping(address => bool) storage whiteList,
        mapping(address => PendingUint192) storage pendingList,
        function(address, bool) internal _setFunction,
        address target,
        bool isWhitelisted
    ) internal returns (bool isSetted) {
        if (whiteList[target] && isWhitelisted) revert VaultErrors.AlreadySet();
        if (pendingList[target].validAt != 0) revert VaultErrors.AlreadyPending();

        if (!isWhitelisted) {
            _setFunction(target, isWhitelisted);
            isSetted = true;
        } else {
            pendingList[target].update(0, _timelock);
        }
    }

    function setCurator(address newCurator) external virtual onlyOwner {
        if (newCurator == _curator) revert VaultErrors.AlreadySet();
        _setCurator(newCurator);
    }

    function _setCurator(address newCurator) internal {
        _curator = newCurator;
        emit VaultEvents.SetCurator(newCurator);
    }

    /**
     * Revoke functions
     */
    function revokePendingTimelock() external virtual onlyGuardianRole {
        delete _pendingTimelock;

        emit VaultEvents.RevokePendingTimelock(_msgSender());
    }

    function revokePendingGuardian() external virtual onlyGuardianRole {
        delete _pendingGuardian;

        emit VaultEvents.RevokePendingGuardian(_msgSender());
    }

    function revokePendingMarket(address market) external virtual onlyGuardianRole {
        delete _pendingMarkets[market];

        emit VaultEvents.RevokePendingMarket(_msgSender(), market);
    }

    function revokePendingPool() external virtual onlyGuardianRole {
        delete _pendingPool;

        emit VaultEventsV2.RevokePendingPool(_msgSender());
    }

    function revokePendingPerformanceFeeRate() external virtual onlyGuardianRole {
        delete _pendingPerformanceFeeRate;

        emit VaultEvents.RevokePendingPerformanceFeeRate(_msgSender());
    }

    /**
     * @notice Revoke pending minimum APY change
     */
    function revokePendingMinApy() external virtual onlyGuardianRole {
        delete _pendingMinApy;

        emit VaultEventsV2.RevokePendingMinApy(_msgSender());
    }

    function acceptTimelock() external virtual afterTimelock(_pendingTimelock.validAt) {
        _setTimelock(_pendingTimelock.value);
    }

    function acceptGuardian() external virtual afterTimelock(_pendingGuardian.validAt) {
        _setGuardian(_pendingGuardian.value);
    }

    function acceptMarket(address market) external virtual afterTimelock(_pendingMarkets[market].validAt) {
        _setMarketWhitelist(market, true);
    }

    function acceptPool() external virtual afterTimelock(_pendingPool.validAt) {
        _setPool(_pendingPool.value);
        delete _pendingPool;
    }

    function acceptPerformanceFeeRate() external virtual afterTimelock(_pendingPerformanceFeeRate.validAt) {
        _setPerformanceFeeRate(uint256(_pendingPerformanceFeeRate.value).toUint64());
        delete _pendingPerformanceFeeRate;
        emit VaultEvents.SetPerformanceFeeRate(_msgSender(), _performanceFeeRate);
    }

    /**
     * @notice Pauses the contract
     */
    function pause() external virtual onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external virtual onlyOwner {
        _unpause();
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
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256 deltaXt)
        external
        virtual
        override
        whenNotPaused
    {
        _delegateCall(
            abi.encodeCall(IOrderManagerV2.afterSwap, (IERC20(asset()), ftReserve, xtReserve, deltaFt, deltaXt))
        );
    }

    function supplyQueueLength() external view virtual returns (uint256) {
        revert VaultErrorsV2.SupplyQueueNoLongerSupported();
    }

    function withdrawQueueLength() external view virtual returns (uint256) {
        revert VaultErrorsV2.WithdrawalQueueNoLongerSupported();
    }

    function pendingPool() external view override returns (PendingAddress memory) {
        return _pendingPool;
    }
}
