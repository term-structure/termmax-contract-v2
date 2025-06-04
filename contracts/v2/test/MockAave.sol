// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAaveV3Minimal} from "../extensions/aave/IAaveV3Minimal.sol";
import {IMintableERC20, IERC20} from "../../v1/tokens/IMintableERC20.sol";

contract MockAave is ERC20, IAaveV3Minimal {
    IERC20 public immutable underlying;

    constructor(address underlying_) ERC20("MockAave", "mAAVE") {
        underlying = IERC20(underlying_);
    }

    function getReserveData(address) external view override returns (ReserveData memory) {
        return ReserveData({
            configuration: ReserveConfigurationMap({data: 0}),
            liquidityIndex: 1e27,
            currentLiquidityRate: 0,
            variableBorrowIndex: 1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            id: 0,
            aTokenAddress: address(this),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(0),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 /* referralCode */ ) external override {
        // Transfer tokens from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        // Mint aTokens to the onBehalfOf address
        _mint(onBehalfOf, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        // Burn aTokens from sender
        _burn(msg.sender, amount);
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < amount) {
            IMintableERC20(asset).mint(address(this), amount - balance);
        }
        // Transfer underlying tokens to the recipient
        IERC20(asset).transfer(to, amount);
        return amount;
    }

    function simulateInterestAccrual(address to, uint256 amount) external {
        // Simulate interest accrual by minting aTokens
        _mint(to, amount);
    }
}
