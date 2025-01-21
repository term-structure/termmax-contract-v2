// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {PendingAddress, PendingUint192} from "../lib/PendingLib.sol";

interface ITermMaxVault is IERC4626 {
    function dealBadDebt(
        address collaretal,
        uint256 badDebtAmt,
        address recipient,
        address owner
    ) external returns (uint256 shares, uint256 collaretalOut);
    function apr() external view returns (uint256);
    // View Functions
    function guardian() external view returns (address);
    function curator() external view returns (address);
    function isAllocator(address) external view returns (bool);
    function marketWhitelist(address) external view returns (bool);
    function timelock() external view returns (uint256);
    function pendingMarkets(address) external view returns (uint192 value, uint64 validAt);
    function pendingTimelock() external view returns (uint192 value, uint64 validAt);
    function pendingPerformanceFeeRate() external view returns (uint192 value, uint64 validAt);
    function pendingGuardian() external view returns (address value, uint64 validAt);
    function maxTerm() external view returns (uint64);
    function performanceFeeRate() external view returns (uint64);

    // OrderManager View Functions
    function totalFt() external view returns (uint256);
    function accretingPrincipal() external view returns (uint256);
    function performanceFee() external view returns (uint256);
    function supplyQueue(uint256) external view returns (address);
    function withdrawQueue(uint256) external view returns (address);
    function orderMapping(
        address
    ) external view returns (ITermMaxMarket market, IERC20 ft, IERC20 xt, uint128 maxSupply, uint64 maturity);
    function badDebtMapping(address) external view returns (uint256);

    // State-Changing Functions
    function createOrder(
        ITermMaxMarket market,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts calldata curveCuts
    ) external returns (ITermMaxOrder order);

    function updateOrders(
        ITermMaxOrder[] calldata orders,
        int256[] calldata changes,
        uint256[] calldata maxSupplies,
        CurveCuts[] calldata curveCuts
    ) external;

    function updateSupplyQueue(uint256[] calldata indexes) external;
    function updateWithdrawQueue(uint256[] calldata indexes) external;
    function redeemOrder(ITermMaxOrder order) external;
    function withdrawPerformanceFee(address recipient, uint256 amount) external;

    function submitGuardian(address newGuardian) external;
    function setCurator(address newCurator) external;
    function submitTimelock(uint256 newTimelock) external;
    function setCapacity(uint256 newCapacity) external;
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;
    function submitPerformanceFeeRate(uint184 newPerformanceFeeRate) external;
    function submitMarket(address market, bool isWhitelisted) external;

    function revokePendingTimelock() external;
    function revokePendingGuardian() external;
    function revokePendingMarket(address market) external;

    function acceptTimelock() external;
    function acceptGuardian() external;
    function acceptMarket(address market) external;
    function acceptPerformanceFeeRate() external;
}
