// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanAave, IAaveFlashLoanCallback} from "./IFlashLoanAave.sol";
import {IFlashLoanMorpho, IMorphoFlashLoanCallback} from "./IFlashLoanMorpho.sol";
import {TransferUtils, IERC20} from "contracts/lib/TransferUtils.sol";
import {ITermMaxRouter, ITermMaxOrder} from "contracts/router/ITermMaxRouter.sol";

contract TradingBot is IAaveFlashLoanCallback, IMorphoFlashLoanCallback {
    using TransferUtils for IERC20;
    using SafeCast for uint256;

    IFlashLoanAave immutable AAVE_POOL;
    address immutable AAVE_ADDRESSES_PROVIDER;
    IFlashLoanMorpho immutable MORPHO;
    ITermMaxRouter immutable termMaxRouter;

    enum BorrowType {
        AAVE,
        MORPHO
    }

    constructor(
        IFlashLoanAave _AAVE_POOL,
        address _AAVE_ADDRESSES_PROVIDER,
        IFlashLoanMorpho _MORPHO,
        ITermMaxRouter _termMaxRouter
    ) {
        AAVE_POOL = _AAVE_POOL;
        AAVE_ADDRESSES_PROVIDER = _AAVE_ADDRESSES_PROVIDER;
        MORPHO = _MORPHO;
        termMaxRouter = _termMaxRouter;
    }

    function doTrade(address asset, uint256 borrowAmount, BorrowType borrowType, bytes memory params) external {
        if (borrowType == BorrowType.AAVE) {
            AAVE_POOL.flashLoanSimple(address(this), asset, borrowAmount, params, 0);
        } else if (borrowType == BorrowType.MORPHO) {
            MORPHO.flashLoan(asset, borrowAmount, abi.encode(asset, params));
        }
    }

    /// @notice morpho callback
    function onMorphoFlashLoan(uint256 assets, bytes memory data) external override {
        (IERC20 token, bytes memory tradeData) = abi.decode(data, (IERC20, bytes));
        _doTrade(token, 0, assets.toUint128(), tradeData);
        token.safeIncreaseAllowance(address(MORPHO), assets);
    }

    function _doTrade(IERC20 token, uint256 premium, uint128 assets, bytes memory data) internal {
        (
            uint256 minIncome,
            IERC20 tradeToken,
            address recipient,
            ITermMaxOrder[] memory buyOrders,
            ITermMaxOrder[] memory sellOrders,
            uint128[] memory tradingAmts,
            uint256 deadline
        ) = abi.decode(data, (uint256, IERC20, address, ITermMaxOrder[], ITermMaxOrder[], uint128[], uint256));
        tradeToken.safeIncreaseAllowance(address(MORPHO), assets);
        token.safeIncreaseAllowance(address(termMaxRouter), assets);
        uint256 cost = termMaxRouter.swapTokenToExactToken(
            token, tradeToken, address(this), buyOrders, tradingAmts, assets, deadline
        );
        tradeToken.safeIncreaseAllowance(address(termMaxRouter), _sumUint128Array(tradingAmts));
        uint256 income = termMaxRouter.swapExactTokenToToken(
            tradeToken,
            token,
            address(this),
            sellOrders,
            tradingAmts,
            (cost + minIncome + premium).toUint128(),
            deadline
        );
        income = income - cost - premium;
        token.safeTransfer(recipient, income);
    }

    /// @notice aave callback
    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata params)
        external
        override
        returns (bool)
    {
        _doTrade(IERC20(asset), premium, amount.toUint128(), params);
        IERC20(asset).safeIncreaseAllowance(address(AAVE_POOL), amount + premium);
        return true;
    }

    function ADDRESSES_PROVIDER() external view returns (address) {
        return AAVE_ADDRESSES_PROVIDER;
    }

    function POOL() external view returns (IFlashLoanAave) {
        return AAVE_POOL;
    }

    function _sumUint128Array(uint128[] memory nums) internal pure returns (uint128) {
        uint128 result = 0;
        for (uint256 i = 0; i < nums.length; i++) {
            result += nums[i];
        }
        return result;
    }
}
