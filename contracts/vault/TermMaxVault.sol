// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PendingLib, PendingAddress, PendingUint192} from "../lib/PendingLib.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {ITermMaxRouter} from "../router/ITermMaxRouter.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {VaultConstants} from "../lib/VaultConstants.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";
import {OrderManager} from "./OrderManager.sol";

contract TermMaxVault is Ownable2Step, ReentrancyGuard, OrderManager, ERC4626 {
    using SafeCast for uint256;
    using TransferUtils for IERC20;

    address public guardian;
    address public curator;

    mapping(address => bool) public isAllocator;

    mapping(address => bool) public marketWhitelist;

    mapping(address => PendingAddress) public pendingMarkets;

    PendingUint192 public pendingTimelock;
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
        address admin,
        IERC20 aseet_,
        string memory name_,
        string memory symbol_
    ) Ownable(admin) ERC4626(aseet_) ERC20(name_, symbol_) {}

    function asset() public view override(ERC4626, OrderManager) returns (address) {
        return ERC4626.asset();
    }

    // OrderManager functions
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
}
