// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVToken is IERC20 {
    function underlying() external view returns (address);

    function mint(uint256 mintAmount) external returns (uint256);

    function mintBehalf(address minter, uint256 mintAllowed) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemBehalf(address redeemer, uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function redeemUnderlyingBehalf(address redeemer, uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function borrowBehalf(address borrower, uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    function liquidateBorrow(address borrower, uint256 repayAmount, address vTokenCollateral)
        external
        returns (uint256);

    function healBorrow(address payer, address borrower, uint256 repayAmount) external;

    function forceLiquidateBorrow(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address vTokenCollateral,
        bool skipCloseFactorCheck
    ) external;

    function seize(address liquidator, address borrower, uint256 seizeTokens) external;

    function transfer(address dst, uint256 amount) external returns (bool);

    function transferFrom(address src, address dst, uint256 amount) external returns (bool);

    function accrueInterest() external returns (uint256);

    function sweepToken(address token) external;

    /**
     * Admin Functions **
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external;

    function reduceReserves(uint256 reduceAmount) external;

    function exchangeRateCurrent() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function addReserves(uint256 addAmount) external;

    function totalBorrowsCurrent() external returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getCash() external view returns (uint256);
}
