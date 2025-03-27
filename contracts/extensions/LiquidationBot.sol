// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanAave, IAaveFlashLoanCallback} from "./IFlashLoanAave.sol";
import {IFlashLoanMorpho, IMorphoFlashLoanCallback} from "./IFlashLoanMorpho.sol";
import {TransferUtils, IERC20} from "contracts/lib/TransferUtils.sol";
import {IGearingToken, GtConfig, IERC20Metadata} from "contracts/tokens/IGearingToken.sol";
import {ISwapAdapter, SwapUnit} from "contracts/router/ISwapAdapter.sol";
import {ITermMaxOrder} from "contracts/ITermMaxOrder.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {GearingTokenConstants} from "contracts/lib/GearingTokenConstants.sol";
import {MathLib} from "contracts/lib/MathLib.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {console} from "forge-std/console.sol";

contract LiquidationBot is IAaveFlashLoanCallback, IMorphoFlashLoanCallback {
    using TransferUtils for IERC20;
    using SafeCast for uint256;
    using MathLib for *;

    error CannotLiquidate();
    error CollateralCannotCoverBorrow();
    error SwapFailed(address adapter, bytes data);

    IFlashLoanAave immutable AAVE_POOL;
    address immutable AAVE_ADDRESSES_PROVIDER;
    IFlashLoanMorpho immutable MORPHO;

    enum BorrowType {
        AAVE,
        MORPHO
    }

    struct PriceInfo {
        uint256 price;
        uint256 priceDenominator;
        uint256 tokenDenominator;
    }

    struct LiquidationParams {
        IGearingToken gt;
        IERC20 debtToken;
        IERC20 collateral;
        uint256 gtId;
        uint256 liquidateAmt;
        IERC20 ft;
        ITermMaxOrder order;
        SwapUnit[] units;
    }

    constructor(IFlashLoanAave _AAVE_POOL, address _AAVE_ADDRESSES_PROVIDER, IFlashLoanMorpho _MORPHO) {
        AAVE_POOL = _AAVE_POOL;
        AAVE_ADDRESSES_PROVIDER = _AAVE_ADDRESSES_PROVIDER;
        MORPHO = _MORPHO;
    }

    function simulateBatchLiquidation(IGearingToken[] calldata gt, uint256[] calldata id)
        external
        view
        returns (
            bool[] memory isLiquidable,
            uint128[] memory maxRepayAmt,
            uint256[] memory cToLiquidator,
            uint256[] memory incomeValue
        )
    {
        isLiquidable = new bool[](gt.length);
        maxRepayAmt = new uint128[](gt.length);
        cToLiquidator = new uint256[](gt.length);
        incomeValue = new uint256[](gt.length);
        for (uint256 i = 0; i < gt.length; i++) {
            (isLiquidable[i], maxRepayAmt[i], cToLiquidator[i], incomeValue[i]) = simulateLiquidation(gt[i], id[i]);
        }
    }

    function simulateLiquidation(IGearingToken gt, uint256 id)
        public
        view
        returns (bool isLiquidable, uint128 maxRepayAmt, uint256 cToLiquidator, uint256 incomeValue)
    {
        (, uint128 debtAmt, uint128 ltv, bytes memory collateralData) = gt.loanInfo(id);
        if (ltv >= Constants.DECIMAL_BASE) {
            return (true, 0, 0, 0);
        }
        (isLiquidable, maxRepayAmt) = gt.getLiquidationInfo(id);
        if (isLiquidable) {
            GtConfig memory gtConfig = gt.getGtConfig();
            PriceInfo memory debtPriceInfo = _getPriceInfo(gtConfig.loanConfig.oracle, address(gtConfig.debtToken));
            PriceInfo memory collateralPriceInfo = _getPriceInfo(gtConfig.loanConfig.oracle, gtConfig.collateral);
            (cToLiquidator, incomeValue) = _calcLiquidationResult(
                debtAmt, abi.decode(collateralData, (uint256)), maxRepayAmt, debtPriceInfo, collateralPriceInfo
            );
        }
    }

    function _getPriceInfo(IOracle oracle, address asset) internal view returns (PriceInfo memory priceInfo) {
        (uint256 price, uint8 decimals) = oracle.getPrice(asset);
        priceInfo.price = price;
        priceInfo.priceDenominator = 10 ** decimals;
        priceInfo.tokenDenominator = 10 ** IERC20Metadata(asset).decimals();
    }

    function _calcLiquidationResult(
        uint256 debtAmt,
        uint256 collateralAmt,
        uint256 repayAmt,
        PriceInfo memory debtPriceInfo,
        PriceInfo memory collateralPriceInfo
    ) internal pure returns (uint256 cToLiquidator, uint256 incomeValue) {
        uint256 ddPriceToCdPrice = (
            debtPriceInfo.price * collateralPriceInfo.priceDenominator * Constants.DECIMAL_BASE_SQ
                + collateralPriceInfo.price * debtPriceInfo.priceDenominator - 1
        ) / (collateralPriceInfo.price * debtPriceInfo.priceDenominator);

        // calculate the amount of collateral that is equivalent to repayAmt
        // with debt to collateral price
        uint256 cEqualRepayAmt = (repayAmt * ddPriceToCdPrice * collateralPriceInfo.tokenDenominator)
            / (debtPriceInfo.tokenDenominator * Constants.DECIMAL_BASE_SQ);

        uint256 rewardToLiquidator =
            (cEqualRepayAmt * GearingTokenConstants.REWARD_TO_LIQUIDATOR) / Constants.DECIMAL_BASE;
        uint256 rewardToProtocol = (cEqualRepayAmt * GearingTokenConstants.REWARD_TO_PROTOCOL) / Constants.DECIMAL_BASE;

        uint256 removedCollateralAmt = cEqualRepayAmt + rewardToLiquidator + rewardToProtocol;

        if (debtAmt == 0) {
            removedCollateralAmt = 0;
        } else {
            removedCollateralAmt = removedCollateralAmt.min((collateralAmt * repayAmt) / debtAmt);
        }

        // Case 1: removed collateral can not cover repayAmt + rewardToLiquidator
        if (removedCollateralAmt <= cEqualRepayAmt + rewardToLiquidator) {
            cToLiquidator = removedCollateralAmt;
        } else {
            cToLiquidator = cEqualRepayAmt + rewardToLiquidator;
        }
        if (cToLiquidator > cEqualRepayAmt) {
            uint256 income = cToLiquidator - cEqualRepayAmt;
            incomeValue = income * collateralPriceInfo.price * Constants.DECIMAL_BASE
                / (collateralPriceInfo.priceDenominator * collateralPriceInfo.tokenDenominator);
        }
    }

    function liquidate(LiquidationParams memory params, BorrowType borrowType) external {
        bytes memory callbackData = abi.encode(msg.sender, params);

        if (borrowType == BorrowType.AAVE) {
            AAVE_POOL.flashLoanSimple(address(this), address(params.debtToken), params.liquidateAmt, callbackData, 0);
        } else if (borrowType == BorrowType.MORPHO) {
            MORPHO.flashLoan(address(params.debtToken), params.liquidateAmt, callbackData);
        }
    }

    /// @notice morpho callback
    function onMorphoFlashLoan(uint256 assets, bytes memory data) external override {
        (address recipient, LiquidationParams memory params) = abi.decode(data, (address, LiquidationParams));
        _doLiquidate(assets.toUint128(), 0, recipient, params);
        params.debtToken.safeIncreaseAllowance(address(MORPHO), assets);
    }

    /// @notice aave callback
    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata data)
        external
        override
        returns (bool)
    {
        (address recipient, LiquidationParams memory params) = abi.decode(data, (address, LiquidationParams));
        _doLiquidate(amount.toUint128(), premium, recipient, params);
        IERC20(asset).safeIncreaseAllowance(address(AAVE_POOL), amount + premium);
        return true;
    }

    function _doLiquidate(uint128 assets, uint256 premium, address recipient, LiquidationParams memory params)
        internal
    {
        uint256 totalAssets;
        if (address(params.ft) != address(0) && address(params.order) != address(0)) {
            // liquidate by ft
            params.debtToken.safeIncreaseAllowance(address(params.order), assets);
            // get remaining assets
            totalAssets = assets
                - params.order.swapTokenToExactToken(
                    params.debtToken, params.ft, address(this), assets, assets, block.timestamp
                );
            params.ft.safeIncreaseAllowance(address(params.gt), assets);
            params.gt.liquidate(params.gtId, assets, false);
        } else {
            // liquidate by debt token
            params.debtToken.safeIncreaseAllowance(address(params.gt), assets);
            params.gt.liquidate(params.gtId, assets, true);
        }
        // swap collateral to debt token
        bytes memory inputData = abi.encode(params.collateral.balanceOf(address(this)));
        totalAssets += abi.decode(_doSwap(inputData, params.units), (uint256));
        uint256 totalCost = assets + premium;
        if (totalAssets < totalCost) {
            revert CollateralCannotCoverBorrow();
        }
        // transfer income to sender
        params.debtToken.safeTransfer(recipient, totalAssets - totalCost);
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

    function _doSwap(bytes memory inputData, SwapUnit[] memory units) internal returns (bytes memory outData) {
        for (uint256 i = 0; i < units.length; ++i) {
            bytes memory dataToSwap =
                abi.encodeCall(ISwapAdapter.swap, (units[i].tokenIn, units[i].tokenOut, inputData, units[i].swapData));

            (bool success, bytes memory returnData) = units[i].adapter.delegatecall(dataToSwap);
            if (!success) {
                revert SwapFailed(units[i].adapter, returnData);
            }
            inputData = abi.decode(returnData, (bytes));
        }
        outData = inputData;
    }
}
