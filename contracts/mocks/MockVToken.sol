// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVToken} from "../v2/extensions/venus/IVToken.sol";

contract MockVToken is ERC20, IVToken {
    address public immutable _underlying;
    uint256 public exchangeRateMock = 1e18;

    mapping(address => uint256) public borrowBalancesMock;
    uint256 public totalBorrowsMock;
    uint256 public totalReservesMock;
    uint256 public reserveFactorMantissaMock;
    uint256 public supplyRateMock;
    uint256 public borrowRateMock;
    uint256 public cashMock;

    uint8 private _decimals = 18;

    constructor(address underlying_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _underlying = underlying_;
    }

    function decimals() public view override(ERC20) returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function underlying() external view override returns (address) {
        return _underlying;
    }

    // --- ERC20 / IVToken Overrides ---

    function transfer(address to, uint256 value) public override(ERC20, IVToken) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, IVToken) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function approve(address spender, uint256 value) public override(ERC20, IVToken) returns (bool) {
        return super.approve(spender, value);
    }

    function allowance(address owner, address spender) public view override(ERC20, IVToken) returns (uint256) {
        return super.allowance(owner, spender);
    }

    function balanceOf(address account) public view override(ERC20, IVToken) returns (uint256) {
        return super.balanceOf(account);
    }

    function increaseAllowance(address spender, uint256 addedValue) public override(IVToken) returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public override(IVToken) returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    // --- VToken Implementation ---

    function mint(uint256 mintAmount) public virtual override returns (uint256) {
        IERC20(_underlying).transferFrom(msg.sender, address(this), mintAmount);
        // mintTokens = mintAmount / exchangeRate
        uint256 vTokenAmount = (mintAmount * 1e18) / exchangeRateMock;
        _mint(msg.sender, vTokenAmount);
        cashMock += mintAmount;
        return 0; // Success
    }

    function mintBehalf(address minter, uint256 mintAmount) external override returns (uint256) {
        IERC20(_underlying).transferFrom(msg.sender, address(this), mintAmount);
        uint256 vTokenAmount = (mintAmount * 1e18) / exchangeRateMock;
        _mint(minter, vTokenAmount);
        cashMock += mintAmount;
        return 0;
    }

    function redeem(uint256 redeemTokens) external override returns (uint256) {
        uint256 redeemAmount = (redeemTokens * exchangeRateMock) / 1e18;
        _burn(msg.sender, redeemTokens);
        IERC20(_underlying).transfer(msg.sender, redeemAmount);
        if (cashMock >= redeemAmount) cashMock -= redeemAmount;
        return 0;
    }

    function redeemBehalf(address redeemer, uint256 redeemTokens) external override returns (uint256) {
        // NOTE: Mock assumes caller has permission or logic is simplified for testing
        uint256 redeemAmount = (redeemTokens * exchangeRateMock) / 1e18;
        _burn(redeemer, redeemTokens);
        IERC20(_underlying).transfer(redeemer, redeemAmount);
        if (cashMock >= redeemAmount) cashMock -= redeemAmount;
        return 0;
    }

    function redeemUnderlying(uint256 redeemAmount) public virtual override returns (uint256) {
        uint256 redeemTokens = (redeemAmount * 1e18) / exchangeRateMock;
        _burn(msg.sender, redeemTokens);
        IERC20(_underlying).transfer(msg.sender, redeemAmount);
        if (cashMock >= redeemAmount) cashMock -= redeemAmount;
        return 0;
    }

    function redeemUnderlyingBehalf(address redeemer, uint256 redeemAmount) external override returns (uint256) {
        uint256 redeemTokens = (redeemAmount * 1e18) / exchangeRateMock;
        _burn(redeemer, redeemTokens);
        IERC20(_underlying).transfer(redeemer, redeemAmount);
        if (cashMock >= redeemAmount) cashMock -= redeemAmount;
        return 0;
    }

    function borrow(uint256 borrowAmount) external override returns (uint256) {
        IERC20(_underlying).transfer(msg.sender, borrowAmount);
        borrowBalancesMock[msg.sender] += borrowAmount;
        totalBorrowsMock += borrowAmount;
        if (cashMock >= borrowAmount) cashMock -= borrowAmount;
        return 0;
    }

    function borrowBehalf(address borrower, uint256 borrowAmount) external override returns (uint256) {
        IERC20(_underlying).transfer(borrower, borrowAmount);
        borrowBalancesMock[borrower] += borrowAmount;
        totalBorrowsMock += borrowAmount;
        if (cashMock >= borrowAmount) cashMock -= borrowAmount;
        return 0;
    }

    function repayBorrow(uint256 repayAmount) external override returns (uint256) {
        IERC20(_underlying).transferFrom(msg.sender, address(this), repayAmount);
        if (borrowBalancesMock[msg.sender] >= repayAmount) borrowBalancesMock[msg.sender] -= repayAmount;
        else borrowBalancesMock[msg.sender] = 0;

        if (totalBorrowsMock >= repayAmount) totalBorrowsMock -= repayAmount;
        else totalBorrowsMock = 0;

        cashMock += repayAmount;
        return 0;
    }

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external override returns (uint256) {
        IERC20(_underlying).transferFrom(msg.sender, address(this), repayAmount);
        if (borrowBalancesMock[borrower] >= repayAmount) borrowBalancesMock[borrower] -= repayAmount;
        else borrowBalancesMock[borrower] = 0;

        if (totalBorrowsMock >= repayAmount) totalBorrowsMock -= repayAmount;
        else totalBorrowsMock = 0;

        cashMock += repayAmount;
        return 0;
    }

    function liquidateBorrow(address borrower, uint256 repayAmount, address vTokenCollateral)
        external
        override
        returns (uint256)
    {
        // Mock liquidation logic
        IERC20(_underlying).transferFrom(msg.sender, address(this), repayAmount);

        if (borrowBalancesMock[borrower] >= repayAmount) borrowBalancesMock[borrower] -= repayAmount;
        else borrowBalancesMock[borrower] = 0;

        if (totalBorrowsMock >= repayAmount) totalBorrowsMock -= repayAmount;
        else totalBorrowsMock = 0;

        cashMock += repayAmount;

        // Seize collateral - simplified
        if (vTokenCollateral == address(this)) {
            uint256 seizeTokens = (repayAmount * 1e18) / exchangeRateMock;
            _transfer(borrower, msg.sender, seizeTokens);
        } else {
            // If cross-market, need to call seize
            try IVToken(vTokenCollateral).seize(msg.sender, borrower, (repayAmount * 1e18) / 1e18) {} catch {}
        }
        return 0;
    }

    function healBorrow(address payer, address borrower, uint256 repayAmount) external override {}

    function forceLiquidateBorrow(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        address vTokenCollateral,
        bool skipCloseFactorCheck
    ) external override {}

    function seize(address liquidator, address borrower, uint256 seizeTokens) external override {
        // Transfer vTokens from borrower to liquidator
        _transfer(borrower, liquidator, seizeTokens);
    }

    function accrueInterest() external override returns (uint256) {
        return 0;
    }

    function sweepToken(address token) external override {}

    function setReserveFactor(uint256 newReserveFactorMantissa) external override {
        reserveFactorMantissaMock = newReserveFactorMantissa;
    }

    function reduceReserves(uint256 reduceAmount) external override {
        if (totalReservesMock >= reduceAmount) totalReservesMock -= reduceAmount;
        IERC20(_underlying).transfer(msg.sender, reduceAmount);
    }

    function exchangeRateCurrent() external view override returns (uint256) {
        return exchangeRateMock;
    }

    function borrowBalanceCurrent(address account) external view override returns (uint256) {
        return borrowBalancesMock[account];
    }

    function addReserves(uint256 addAmount) external override {
        IERC20(_underlying).transferFrom(msg.sender, address(this), addAmount);
        totalReservesMock += addAmount;
        cashMock += addAmount;
    }

    function totalBorrowsCurrent() external view override returns (uint256) {
        return totalBorrowsMock;
    }

    function balanceOfUnderlying(address owner) external view override returns (uint256) {
        return (balanceOf(owner) * exchangeRateMock) / 1e18;
    }

    function getAccountSnapshot(address account) external view override returns (uint256, uint256, uint256, uint256) {
        return (0, balanceOf(account), borrowBalancesMock[account], exchangeRateMock);
    }

    function borrowRatePerBlock() external view override returns (uint256) {
        return borrowRateMock;
    }

    function supplyRatePerBlock() external view override returns (uint256) {
        return supplyRateMock;
    }

    function borrowBalanceStored(address account) external view override returns (uint256) {
        return borrowBalancesMock[account];
    }

    function exchangeRateStored() external view override returns (uint256) {
        return exchangeRateMock;
    }

    function getCash() external view override returns (uint256) {
        return cashMock;
    }

    // Helper to set exchange rate for test
    function setExchangeRate(uint256 rate) external {
        exchangeRateMock = rate;
    }
}
