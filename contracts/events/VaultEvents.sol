// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CurveCuts} from "../storage/TermMaxStorage.sol";

interface VaultEvents {
    event SubmitGuardian(address newGuardian);
    event SetCapacity(address indexed caller, uint256 newCapacity);

    event SetCurator(address newCurator);
    event SubmitMarket(address indexed market, bool isWhitelisted);
    event RevokePendingMarket(address indexed caller, address indexed market);

    event SetPerformanceFeeRate(address indexed caller, uint256 newPerformanceFeeRate);

    event SubmitPerformanceFeeRate(uint256 newPerformanceFeeRate);

    event SetMarketWhitelist(address indexed caller, address indexed market, bool isWhitelisted);

    event CreateOrder(
        address indexed caller,
        address indexed market,
        address indexed order,
        uint256 maxSupply,
        uint256 initialReserve,
        CurveCuts curveCuts
    );
    event UpdateOrder(
        address indexed caller,
        address indexed order,
        int256 changes,
        uint256 maxSupply,
        CurveCuts curveCuts
    );
    event DealBadDebt(
        address indexed caller,
        address indexed recipient,
        address indexed collaretal,
        uint256 badDebt,
        uint256 shares,
        uint256 collateralOut
    );
    event RedeemOrder(address indexed caller, address indexed order, uint128 ftAmt, uint128 redeemedAmt);

    event WithdrawPerformanceFee(address indexed caller, address indexed recipient, uint256 amount);

    event SubmitTimelock(uint256 newTimelock);
    event SetTimelock(address indexed caller, uint256 newTimelock);
    event SetGuardian(address indexed caller, address newGuardian);
    event RevokePendingTimelock(address indexed caller);
    event RevokePendingGuardian(address indexed caller);
    event SetCap(address indexed caller, address indexed order, uint256 newCap);
    event SetIsAllocator(address indexed allocator, bool newIsAllocator);
    event UpdateSupplyQueue(address indexed caller, address[] newSupplyQueue);
    event UpdateWithdrawQueue(address indexed caller, address[] newWithdrawQueue);
}
