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
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
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
import {VaultStorageV2, OrderInfo} from "../../v2/vault/VaultStorageV2.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {ITermMaxVault} from "../../v1/vault/ITermMaxVault.sol";
import {ITermMaxVaultV2} from "./ITermMaxVaultV2.sol";
import {VaultErrorsV2} from "../errors/VaultErrorsV2.sol";
import {TransactionReentrancyGuard} from "../lib/TransactionReentrancyGuard.sol";

contract TermMaxVaultV2 is
    VaultStorageV2,
    ITermMaxVault,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    VaultErrors,
    VaultEvents,
    ISwapCallback,
    ITermMaxVaultV2,
    TransactionReentrancyGuard
{
    using SafeCast for uint256;
    using TransferUtils for IERC20;
    using PendingLib for *;

    address public immutable ORDER_MANAGER_SINGLETON;

    uint256 private constant ACTION_DEPOSIT = uint256(keccak256("ACTION_DEPOSIT"));
    uint256 private constant ACTION_WITHDRAW = uint256(keccak256("ACTION_WITHDRAW"));

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

    function initialize(VaultInitialParamsV2 memory params) external virtual initializer {
        __ERC20_init(params.name, params.symbol);
        __Ownable_init(params.admin);
        __ERC4626_init(params.asset);
        __ReentrancyGuard_init();
        __Pausable_init();

        _setPerformanceFeeRate(params.performanceFeeRate);
        _checkTimelockBounds(params.timelock);
        _setTimelock(params.timelock);
        _setMinApy(params.minApy);
        _setMinIdleFundRate(params.minIdleFundRate);
        _setGuardian(params.guardian);
        _setCapacity(params.maxCapacity);
        _setCurator(params.curator);
    }

    function initialize(VaultInitialParams memory) external virtual initializer {
        revert VaultErrorsV2.UseVaultInitialParamsV2();
    }

    function _setPerformanceFeeRate(uint64 newPerformanceFeeRate) internal {
        _delegateCall(abi.encodeCall(IOrderManager.accruedInterest, ()));
        _performanceFeeRate = newPerformanceFeeRate;
    }

    /// @notice View functions

    /**
     * @inheritdoc ITermMaxVault
     */
    function guardian() external view virtual returns (address) {
        return _guardian;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function curator() external view virtual returns (address) {
        return _curator;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function isAllocator(address allocator) external view virtual returns (bool) {
        return _isAllocator[allocator];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function marketWhitelist(address market) external view virtual returns (bool) {
        return _marketWhitelist[market];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function timelock() external view virtual returns (uint256) {
        return _timelock;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingMarkets(address market) external view virtual returns (PendingUint192 memory) {
        return _pendingMarkets[market];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingTimelock() external view virtual returns (PendingUint192 memory) {
        return _pendingTimelock;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingPerformanceFeeRate() external view virtual returns (PendingUint192 memory) {
        return _pendingPerformanceFeeRate;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function pendingGuardian() external view virtual returns (PendingAddress memory) {
        return _pendingGuardian;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function performanceFeeRate() external view virtual returns (uint64) {
        return _performanceFeeRate;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function totalFt() external view virtual returns (uint256) {
        return _totalFt / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function accretingPrincipal() external view virtual returns (uint256) {
        (uint256 ap,) = _previewAccruedInterest();
        return ap / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function annualizedInterest() external view virtual returns (uint256) {
        return _annualizedInterest / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function performanceFee() external view virtual returns (uint256) {
        (, uint256 pf) = _previewAccruedInterest();
        return pf / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function supplyQueue(uint256) external view virtual returns (address) {
        revert VaultErrorsV2.SupplyQueueNoLongerSupported();
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function withdrawQueue(uint256) external view virtual returns (address) {
        revert VaultErrorsV2.WithdrawalQueueNoLongerSupported();
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function orderMapping(address order) external view virtual returns (OrderInfo memory) {
        return _orderMapping[order];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function badDebtMapping(address collateral) external view virtual returns (uint256) {
        return _badDebtMapping[collateral];
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function apr() external view virtual returns (uint256) {
        revert VaultErrorsV2.UseApyInsteadOfApr();
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function apy() external view virtual override returns (uint256) {
        if (_accretingPrincipal == 0) return 0;
        return (_annualizedInterest * (Constants.DECIMAL_BASE - _performanceFeeRate)) / (_accretingPrincipal);
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
    function minIdleFundRate() external view virtual override returns (uint64) {
        return _minIdleFundRate;
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
    function pendingMinIdleFundRate() external view virtual override returns (PendingUint192 memory) {
        return _pendingMinIdleFundRate;
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function submitPendingMinApy(uint64 newMinApy) external virtual override onlyCuratorRole {
        if (newMinApy == _minApy) revert AlreadySet();
        if (_pendingMinApy.validAt != 0) revert AlreadyPending();

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
    function submitPendingMinIdleFundRate(uint64 newMinIdleFundRate) external virtual override onlyCuratorRole {
        if (newMinIdleFundRate == _minIdleFundRate) revert AlreadySet();
        if (_pendingMinIdleFundRate.validAt != 0) revert AlreadyPending();

        if (newMinIdleFundRate > _minIdleFundRate) {
            _setMinIdleFundRate(newMinIdleFundRate);
        } else {
            _pendingMinIdleFundRate.update(uint184(newMinIdleFundRate), _timelock);
            emit VaultEventsV2.SubmitMinIdleFundRate(newMinIdleFundRate, _pendingMinIdleFundRate.validAt);
        }
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function acceptPendingMinApy() external virtual override afterTimelock(_pendingMinApy.validAt) {
        _setMinApy(uint64(_pendingMinApy.value));
        delete _pendingMinApy;
    }

    /**
     * @inheritdoc ITermMaxVaultV2
     */
    function acceptPendingMinIdleFundRate() external virtual override afterTimelock(_pendingMinIdleFundRate.validAt) {
        _setMinIdleFundRate(uint64(_pendingMinIdleFundRate.value));
        delete _pendingMinIdleFundRate;
    }

    /// @dev Sets `_minApy` to `newMinApy`.
    function _setMinApy(uint64 newMinApy) internal {
        _minApy = newMinApy;
        emit VaultEventsV2.SetMinApy(_msgSender(), newMinApy);
    }

    /// @dev Sets `_minIdleFundRate` to `newMinIdleFundRate`.
    function _setMinIdleFundRate(uint64 newMinIdleFundRate) internal {
        _minIdleFundRate = newMinIdleFundRate;
        emit VaultEventsV2.SetMinIdleFundRate(_msgSender(), newMinIdleFundRate);
    }

    // Ordermanager functions
    /**
     * @inheritdoc ITermMaxVault
     */
    function createOrder(ITermMaxMarket market, uint256 maxSupply, uint256 initialReserve, CurveCuts memory curveCuts)
        external
        virtual
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
    ) external virtual onlyCuratorRole whenNotPaused {
        _delegateCall(
            abi.encodeCall(IOrderManager.updateOrders, (IERC20(asset()), orders, changes, maxSupplies, curveCuts))
        );
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function redeemOrder(ITermMaxOrder order) external virtual {
        _delegateCall(abi.encodeCall(IOrderManager.redeemOrder, (order)));
    }

    /**
     * @inheritdoc ITermMaxVault
     */
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

    /**
     * @inheritdoc ITermMaxVault
     */
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
    function submitTimelock(uint256 newTimelock) external virtual onlyCuratorRole {
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
    function setCapacity(uint256 newCapacity) external virtual onlyCuratorRole {
        if (newCapacity == _maxCapacity) revert AlreadySet();
        _setCapacity(newCapacity);
    }

    function _setCapacity(uint256 newCapacity) internal {
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
    function submitPerformanceFeeRate(uint184 newPerformanceFeeRate) external virtual onlyCuratorRole {
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
    function submitGuardian(address newGuardian) external virtual onlyOwner {
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
    function submitMarket(address market, bool isWhitelisted) external virtual onlyCuratorRole {
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
    function setIsAllocator(address newAllocator, bool newIsAllocator) external virtual onlyOwner {
        if (_isAllocator[newAllocator] == newIsAllocator) revert AlreadySet();

        _isAllocator[newAllocator] = newIsAllocator;

        emit SetIsAllocator(newAllocator, newIsAllocator);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function setCurator(address newCurator) external virtual onlyOwner {
        if (newCurator == _curator) revert AlreadySet();
        _setCurator(newCurator);
    }

    function _setCurator(address newCurator) internal {
        _curator = newCurator;
        emit SetCurator(newCurator);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function updateSupplyQueue(uint256[] memory) external virtual onlyAllocatorRole {
        revert VaultErrorsV2.SupplyQueueNoLongerSupported();
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function updateWithdrawQueue(uint256[] memory) external virtual onlyAllocatorRole {
        revert VaultErrorsV2.WithdrawalQueueNoLongerSupported();
    }

    /**
     * Revoke functions
     */

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingTimelock() external virtual onlyGuardianRole {
        delete _pendingTimelock;

        emit RevokePendingTimelock(_msgSender());
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingGuardian() external virtual onlyGuardianRole {
        delete _pendingGuardian;

        emit RevokePendingGuardian(_msgSender());
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingMarket(address market) external virtual onlyGuardianRole {
        delete _pendingMarkets[market];

        emit RevokePendingMarket(_msgSender(), market);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function revokePendingPerformanceFeeRate() external virtual onlyGuardianRole {
        delete _pendingPerformanceFeeRate;

        emit RevokePendingPerformanceFeeRate(_msgSender());
    }

    /**
     * @notice Revoke pending minimum APY change
     */
    function revokePendingMinApy() external virtual onlyGuardianRole {
        delete _pendingMinApy;

        emit VaultEventsV2.RevokePendingMinApy(_msgSender());
    }

    /**
     * @notice Revoke pending minimum idle fund rate change
     */
    function revokePendingMinIdleFundRate() external virtual onlyGuardianRole {
        delete _pendingMinIdleFundRate;

        emit VaultEventsV2.RevokePendingMinIdleFundRate(_msgSender());
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptTimelock() external virtual afterTimelock(_pendingTimelock.validAt) {
        _setTimelock(_pendingTimelock.value);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptGuardian() external virtual afterTimelock(_pendingGuardian.validAt) {
        _setGuardian(_pendingGuardian.value);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptMarket(address market) external virtual afterTimelock(_pendingMarkets[market].validAt) {
        _setMarketWhitelist(market, true);
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function acceptPerformanceFeeRate() external virtual afterTimelock(_pendingPerformanceFeeRate.validAt) {
        _setPerformanceFeeRate(uint256(_pendingPerformanceFeeRate.value).toUint64());
        delete _pendingPerformanceFeeRate;
        emit SetPerformanceFeeRate(_msgSender(), _performanceFeeRate);
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
    function afterSwap(uint256 ftReserve, uint256 xtReserve, int256 deltaFt, int256)
        external
        virtual
        override
        whenNotPaused
    {
        _delegateCall(abi.encodeCall(IOrderManager.afterSwap, (ftReserve, xtReserve, deltaFt)));
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function supplyQueueLength() external view virtual returns (uint256) {
        revert VaultErrorsV2.SupplyQueueNoLongerSupported();
    }

    /**
     * @inheritdoc ITermMaxVault
     */
    function withdrawQueueLength() external view virtual returns (uint256) {
        revert VaultErrorsV2.WithdrawalQueueNoLongerSupported();
    }
}
