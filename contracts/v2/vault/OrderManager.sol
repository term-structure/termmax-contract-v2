// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PendingLib, PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {VaultErrors} from "../errors/VaultErrors.sol";
import {VaultEvents} from "../events/VaultEvents.sol";
import {ITermMaxRouter} from "../router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {VaultConstants} from "../lib/VaultConstants.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";

abstract contract OrderManager is VaultErrors, VaultEvents, Ownable2StepUpgradeable {
    using PendingLib for *;
    using TransferUtils for IERC20;
    using SafeCast for uint256;

    struct OrderCapacity {
        uint128 supply;
        uint128 used;
    }

    address public guardian;
    address public curator;

    address[] public supplyQueue;
    address[] public withdrawQueue;

    mapping(address => OrderCapacity) public orderCapacity;

    mapping(address => bool) public isAllocator;

    PendingUint192 public pendingTimelock;
    PendingAddress public pendingGuardian;

    uint256 public timelock;

    ITermMaxRouter public router;

    uint64 public maturity;

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

    /// @dev Makes sure conditions are met to accept a pending value.
    /// @dev Reverts if:
    /// - there's no pending value;
    /// - the timelock has not elapsed since the pending value has been submitted.
    modifier afterTimelock(uint256 validAt) {
        if (validAt == 0) revert NoPendingValue();
        if (block.timestamp < validAt) revert TimelockNotElapsed();
        _;
    }

    function createOrder(
        ITermMaxMarket market,
        uint256 maxXtReserve,
        uint256 capacity,
        CurveCuts memory curveCuts
    ) external onlyCuratorRole returns (ITermMaxOrder order) {
        if (market.config().maturity > maturity) revert MarketIsLaterThanMaturity();
        if (capacity == 0) revert CapacityCannotSetToZero();
        if (
            supplyQueue.length >= VaultConstants.MAX_QUEUE_LENGTH ||
            withdrawQueue.length >= VaultConstants.MAX_QUEUE_LENGTH
        ) revert MaxQueueLengthExceeded();
        (, IERC20 xt, , , IERC20 debtToken) = market.tokens();
        if (asset() != address(debtToken)) revert InconsistentAsset();
        uint xtToDeposit = xt.balanceOf(address(this));
        if (xtToDeposit > capacity) {
            xtToDeposit = capacity;
        }
        if (xtToDeposit > 0) {
            xt.safeIncreaseAllowance(address(router), xtToDeposit);
        }
        order = router.createOrderAndDeposit(
            market,
            address(this),
            maxXtReserve,
            0,
            0,
            xtToDeposit.toUint128(),
            curveCuts
        );

        supplyQueue.push(address(order));
        withdrawQueue.push(address(order));
        orderCapacity[address(order)] = OrderCapacity({supply: capacity.toUint128(), used: xtToDeposit.toUint128()});
    }

    function asset() public view virtual returns (address);

    function supplyQueueLength() external view returns (uint256) {
        return supplyQueue.length;
    }

    function withdrawQueueLength() external view returns (uint256) {
        return withdrawQueue.length;
    }

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

    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > VaultConstants.MAX_TIMELOCK) revert AboveMaxTimelock();
        if (newTimelock < VaultConstants.POST_INITIALIZATION_MIN_TIMELOCK) revert BelowMinTimelock();
    }

    /// @dev Sets `guardian` to `newGuardian`.
    function _setGuardian(address newGuardian) internal {
        guardian = newGuardian;

        emit SetGuardian(_msgSender(), newGuardian);

        delete pendingGuardian;
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

    function acceptTimelock() external afterTimelock(pendingTimelock.validAt) {
        _setTimelock(pendingTimelock.value);
    }

    function acceptGuardian() external afterTimelock(pendingGuardian.validAt) {
        _setGuardian(pendingGuardian.value);
    }

    function setCap(address[] calldata orderAddresses, uint128[] calldata newSupplyCaps) external onlyCuratorRole {
        address sender = _msgSender();
        for (uint256 i = 0; i < orderAddresses.length; i++) {
            address orderAddress = orderAddresses[i];
            uint128 newSupplyCap = newSupplyCaps[i];
            OrderCapacity memory capacity = orderCapacity[orderAddress];
            if (capacity.supply == 0) {
                revert UnauthorizedOrder(orderAddress);
            }

            if (newSupplyCap == 0) {
                revert CapacityCannotSetToZero();
            }

            if (newSupplyCap < capacity.used) {
                revert CapacityCannotLessThanUsed();
            }

            capacity.supply = newSupplyCap;
            orderCapacity[orderAddress] = capacity;

            emit SetCap(sender, orderAddress, newSupplyCap);
        }
    }
}
