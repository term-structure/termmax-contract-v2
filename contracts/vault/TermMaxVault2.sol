// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC4626, ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PendingLib, PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts, VaultInitialParams} from "../storage/TermMaxStorage.sol";
import {ITermMaxRouter} from "../router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {VaultConstants} from "../lib/VaultConstants.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";
import {ISwapCallback} from "contracts/ISwapCallback.sol";
import {VaultErrors} from "../errors/VaultErrors.sol";
import {VaultEvents} from "../events/VaultEvents.sol";
import {IOrderManager} from "./IOrderManager.sol";
import {VaultStorage} from "./VaultStorage.sol";
import {Constants} from "../lib/Constants.sol";

contract TermMaxVault2 is
    Ownable2Step,
    ReentrancyGuard,
    VaultStorage,
    VaultErrors,
    VaultEvents,
    ERC4626,
    Pausable,
    ISwapCallback
{
    using SafeCast for uint256;
    using TransferUtils for IERC20;
    using PendingLib for *;

    address private immutable ORDER_MANAGER_SINGLETON;

    modifier onlyCuratorRole() {
        address sender = _msgSender();
        if (sender != curator && sender != owner()) revert NotCuratorRole();
        _;
    }

    /// @dev Reverts if the caller doesn't have the guardian role.
    modifier onlyGuardianRole() {
        address sender = _msgSender();
        if (sender != guardian && sender != owner()) revert NotGuardianRole();

        _;
    }

    /// @dev Reverts if the caller doesn't have the allocator role.
    modifier onlyAllocatorRole() {
        address sender = _msgSender();
        if (!isAllocator[sender] && sender != curator && sender != owner()) {
            revert NotAllocatorRole();
        }
        _;
    }

    modifier marketIsWhitelisted(address market) {
        if (pendingMarkets[market].validAt != 0 && block.timestamp > pendingMarkets[market].validAt) {
            marketWhitelist[market] = true;
        }
        if (!marketWhitelist[market]) revert MarketNotWhitelisted();
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

    constructor(
        VaultInitialParams memory params
    ) Ownable(params.admin) ERC4626(params.asset) ERC20(params.name, params.symbol) {
        _checkTimelockBounds(params.timelock);
        _setPerformanceFeeRate(params.performanceFeeRate);
        timelock = params.timelock;
        maxCapacity = params.maxCapacity;
        curator = params.curator;
    }

    function _setPerformanceFeeRate(uint64 newPerformanceFeeRate) internal {
        if (newPerformanceFeeRate > VaultConstants.MAX_PERFORMANCE_FEE_RATE) revert PerformanceFeeRateExceeded();
        performanceFeeRate = newPerformanceFeeRate;
    }

    // /**
    //  * @inheritdoc ITermMaxVault
    //  */
    function apr() external view returns (uint256) {
        return (annualizedInterest * Constants.DECIMAL_BASE) / (accretingPrincipal + performanceFee);
    }

    // BaseVault functions
    // /**
    //  * @inheritdoc ITermMaxVault
    //  */
    function createOrder(
        ITermMaxMarket market,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external onlyCuratorRole marketIsWhitelisted(address(market)) whenNotPaused returns (ITermMaxOrder order) {
        order = abi.decode(
            _delegateCall(
                abi.encodeCall(
                    IOrderManager.createOrder,
                    (IERC20(asset()), market, maxSupply, initialReserve, curveCuts)
                )
            ),
            (ITermMaxOrder)
        );
    }

    // /**
    //  * @inheritdoc ITermMaxVault
    //  */
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

    function updateSupplyQueue(uint256[] memory indexes) external onlyAllocatorRole {
        _updateSupplyQueue(indexes);
    }

    function updateWithdrawQueue(uint256[] memory indexes) external onlyAllocatorRole {
        _updateWithdrawQueue(indexes);
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

    // /**
    //  * @inheritdoc ITermMaxVault
    //  */
    function redeemOrder(ITermMaxOrder order) external onlyCuratorRole {
        _delegateCall(abi.encodeCall(IOrderManager.redeemOrder, (order)));
    }

    // /**
    //  * @inheritdoc ITermMaxVault
    //  */
    function withdrawPerformanceFee(address recipient, uint256 amount) external onlyCuratorRole {
        _delegateCall(abi.encodeCall(IOrderManager.withdrawPerformanceFee, (IERC20(asset()), recipient, amount)));
    }

    // ERC4626 functions

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view override returns (uint256) {
        return maxCapacity - totalAssets();
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view override returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    /**
     * @dev Get total assets, falling back to real assets if virtual assets exceed limit
     */
    function totalAssets() public view override returns (uint256) {
        (uint256 previewPrincipal, uint256 previewPerformanceFee) = _previewAccruedInterest();
        return previewPrincipal + previewPerformanceFee;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address recipient,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant whenNotPaused {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);

        _delegateCall(abi.encodeCall(IOrderManager.depositAssets, (IERC20(asset()), assets)));
        _mint(recipient, shares);

        emit Deposit(caller, recipient, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _delegateCall(abi.encodeCall(IOrderManager.withdrawAssets, (IERC20(asset()), receiver, assets)));
        _burn(owner, shares);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _delegateCall(bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = ORDER_MANAGER_SINGLETON.delegatecall(data);
        if (!success) revert(string(returnData));
        return returnData;
    }

    function dealBadDebt(
        address collaretal,
        uint256 badDebtAmt,
        address recipient,
        address owner
    ) external nonReentrant returns (uint256 shares, uint256 collaretalOut) {
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

        collaretalOut = abi.decode(
            _delegateCall(abi.encodeCall(IOrderManager.dealBadDebt, (recipient, collaretal, badDebtAmt))),
            (uint256)
        );

        emit DealBadDebt(caller, recipient, collaretal, badDebtAmt, shares, collaretalOut);
    }

    // Guardian functions
    function _setTimelock(uint256 newTimelock) internal {
        timelock = newTimelock;

        emit SetTimelock(msg.sender, newTimelock);

        delete pendingTimelock;
    }

    function submitTimelock(uint256 newTimelock) external onlyCuratorRole {
        if (newTimelock == timelock) revert AlreadySet();
        if (pendingTimelock.validAt != 0) revert AlreadyPending();
        _checkTimelockBounds(newTimelock);

        if (newTimelock > timelock) {
            _setTimelock(newTimelock);
        } else {
            // Safe "unchecked" cast because newTimelock <= MAX_TIMELOCK.
            pendingTimelock.update(uint184(newTimelock), timelock);

            emit SubmitTimelock(newTimelock);
        }
    }

    function setCapacity(uint256 newCapacity) external onlyCuratorRole {
        if (newCapacity == maxCapacity) revert AlreadySet();
        maxCapacity = newCapacity;
        emit SetCapacity(_msgSender(), newCapacity);
    }

    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > VaultConstants.MAX_TIMELOCK) revert AboveMaxTimelock();
        if (newTimelock < VaultConstants.POST_INITIALIZATION_MIN_TIMELOCK) revert BelowMinTimelock();
    }

    function submitPerformanceFeeRate(uint184 newPerformanceFeeRate) external onlyCuratorRole {
        if (newPerformanceFeeRate == performanceFeeRate) revert AlreadySet();
        if (pendingPerformanceFeeRate.validAt != 0) revert AlreadyPending();
        if (newPerformanceFeeRate < performanceFeeRate) {
            _setPerformanceFeeRate(uint(newPerformanceFeeRate).toUint64());
            emit SetPerformanceFeeRate(_msgSender(), newPerformanceFeeRate);
            return;
        } else {
            pendingPerformanceFeeRate.update(newPerformanceFeeRate, block.timestamp + timelock);
            emit SubmitPerformanceFeeRate(newPerformanceFeeRate);
        }
    }

    function submitGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == guardian) revert AlreadySet();
        if (pendingGuardian.validAt != 0) revert AlreadyPending();

        if (guardian == address(0)) {
            _setGuardian(newGuardian);
        } else {
            pendingGuardian.update(newGuardian, timelock);

            emit SubmitGuardian(newGuardian);
        }
    }

    /// @dev Sets `guardian` to `newGuardian`.
    function _setGuardian(address newGuardian) internal {
        guardian = newGuardian;
        emit SetGuardian(_msgSender(), newGuardian);

        delete pendingGuardian;
    }

    function submitMarket(address market, bool isWhitelisted) external onlyCuratorRole {
        if (marketWhitelist[market] && isWhitelisted) revert AlreadySet();
        if (pendingMarkets[market].validAt != 0) revert AlreadyPending();
        if (!isWhitelisted) {
            _setMarketWhitelist(market, isWhitelisted);
        } else {
            pendingMarkets[market].update(uint184(block.timestamp + timelock), 0);
            emit SubmitMarket(market, isWhitelisted);
        }
    }

    function _setMarketWhitelist(address market, bool isWhitelisted) internal {
        marketWhitelist[market] = isWhitelisted;
        emit SetMarketWhitelist(_msgSender(), market, isWhitelisted);
        delete pendingMarkets[market];
    }

    function setIsAllocator(address newAllocator, bool newIsAllocator) external onlyOwner {
        if (isAllocator[newAllocator] == newIsAllocator) revert AlreadySet();

        isAllocator[newAllocator] = newIsAllocator;

        emit SetIsAllocator(newAllocator, newIsAllocator);
    }

    function setCurator(address newCurator) external onlyOwner {
        if (newCurator == curator) revert AlreadySet();

        curator = newCurator;

        emit SetCurator(newCurator);
    }

    /** Revoke functions */
    function revokePendingTimelock() external onlyGuardianRole {
        delete pendingTimelock;

        emit RevokePendingTimelock(_msgSender());
    }

    function revokePendingGuardian() external onlyGuardianRole {
        delete pendingGuardian;

        emit RevokePendingGuardian(_msgSender());
    }

    function revokePendingMarket(address market) external onlyGuardianRole {
        delete pendingMarkets[market];

        emit RevokePendingMarket(_msgSender(), market);
    }

    function acceptTimelock() external afterTimelock(pendingTimelock.validAt) {
        _setTimelock(pendingTimelock.value);
    }

    function acceptGuardian() external afterTimelock(pendingGuardian.validAt) {
        _setGuardian(pendingGuardian.value);
    }

    function acceptMarket(address market) external afterTimelock(pendingMarkets[market].validAt) {
        _setMarketWhitelist(market, true);
    }

    function acceptPerformanceFeeRate() external afterTimelock(pendingPerformanceFeeRate.validAt) {
        _setPerformanceFeeRate(uint(pendingPerformanceFeeRate.value).toUint64());
        delete pendingPerformanceFeeRate;
        emit SetPerformanceFeeRate(_msgSender(), performanceFeeRate);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _previewAccruedInterest() internal view returns (uint256 previewPrincipal, uint256 previewPerformanceFee) {
        uint64 currentTime = block.timestamp.toUint64();

        uint lastTime = lastUpdateTime;
        if (lastTime == 0) {
            return (0, 0);
        }
        uint64 recentMaturity = recentestMaturity;
        uint previewAnualizedInterest = annualizedInterest;
        previewPrincipal = accretingPrincipal;
        previewPerformanceFee = performanceFee;

        while (currentTime >= recentMaturity && recentMaturity != 0) {
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
                currentTime,
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

    /// @notice Callback function for the swap
    /// @param deltaFt The change in the ft balance of the order
    function swapCallback(int256 deltaFt, int256) external override {
        _delegateCall(abi.encodeCall(IOrderManager.swapCallback, (deltaFt)));
    }
}
