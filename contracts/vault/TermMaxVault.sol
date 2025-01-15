// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
import {BaseVault} from "./BaseVault.sol";
// import {ITermMaxVault} from "./ITermMaxVault.sol";

contract TermMaxVault is Ownable2Step, ReentrancyGuard, BaseVault, ERC4626 {
    using SafeCast for uint256;
    using TransferUtils for IERC20;
    using PendingLib for *;

    address public guardian;
    address public curator;

    mapping(address => bool) public isAllocator;

    mapping(address => bool) public marketWhitelist;

    mapping(address => PendingUint192) public pendingMarkets;

    PendingUint192 public pendingTimelock;
    PendingUint192 public pendingCuratorPercentage;
    PendingAddress public pendingGuardian;

    uint256 public timelock;
    uint256 private maxCapacity;

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
    )
        Ownable(params.admin)
        ERC4626(params.asset)
        ERC20(params.name, params.symbol)
        BaseVault(params.maxTerm, params.curatorPercentage)
    {
        _checkTimelockBounds(params.timelock);
        timelock = params.timelock;
        maxCapacity = params.maxCapacity;
    }

    function asset() public view override(ERC4626, BaseVault) returns (address) {
        return ERC4626.asset();
    }

    // BaseVault functions
    function createOrder(
        ITermMaxMarket market,
        uint256 maxXtReserve,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts memory curveCuts
    ) external override onlyCuratorRole returns (ITermMaxOrder order) {
        return _createOrder(ITermMaxMarket(market), maxXtReserve, maxSupply, initialReserve, curveCuts);
    }

    function updateOrders(
        ITermMaxOrder[] memory orders,
        int256[] memory changes,
        uint256[] memory maxSupplies,
        uint256[] memory maxXtReserves,
        CurveCuts[] memory curveCuts
    ) external override onlyCuratorRole {
        _accruedInterest();
        for (uint256 i = 0; i < orders.length; ++i) {
            _updateOrder(ITermMaxOrder(orders[i]), changes[i], maxSupplies[i], maxXtReserves[i], curveCuts[i]);
        }
    }

    function updateSupplyQueue(uint256[] memory indexes) external override onlyAllocatorRole {
        _updateSupplyQueue(indexes);
    }

    function updateWithdrawQueue(uint256[] memory indexes) external override onlyAllocatorRole {
        _updateWithdrawQueue(indexes);
    }

    function redeemOrder(ITermMaxOrder order) external override onlyCuratorRole {
        _redeemFromMarket(address(order), orderMapping[address(order)]);
    }

    function withdrawIncentive(address recipient, uint256 amount) external override onlyCuratorRole {
        _accruedInterest();
        _withdrawIncentive(recipient, amount);
    }

    // ERC4626 functions

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit(address) public view override(IERC4626, ERC4626) returns (uint256) {
        return maxCapacity - totalAssets();
    }

    /** @dev See {IERC4626-maxMint}. */
    function maxMint(address) public view override(IERC4626, ERC4626) returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    /**
     * @dev Get total assets, falling back to real assets if virtual assets exceed limit
     */
    function totalAssets() public view override(IERC4626, ERC4626) returns (uint256) {
        return lpersFt + curatorIncentive;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override nonReentrant {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        _accruedInterest();
        _mint(receiver, shares);
        _depositAssets(assets);
        emit Deposit(caller, receiver, assets, shares);
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
        _accruedInterest();

        _burn(owner, shares);
        _withdrawAssets(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
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

    function submitCuratorPercentage(uint184 newCuratorPercentage) external onlyCuratorRole {
        if (newCuratorPercentage == curatorPercentage) revert AlreadySet();
        if (pendingCuratorPercentage.validAt != 0) revert AlreadyPending();
        if (newCuratorPercentage < curatorPercentage) {
            _setCuratorPercentage(uint(newCuratorPercentage).toUint64());
            emit SetCuratorPercentage(_msgSender(), newCuratorPercentage);
            return;
        } else {
            pendingCuratorPercentage.update(newCuratorPercentage, block.timestamp + timelock);
            emit SubmitCuratorPercentage(newCuratorPercentage);
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

    function acceptCuratorPercentage() external afterTimelock(pendingCuratorPercentage.validAt) {
        _setCuratorPercentage(uint(pendingCuratorPercentage.value).toUint64());
        delete pendingCuratorPercentage;
        emit SetCuratorPercentage(_msgSender(), curatorPercentage);
    }
}
