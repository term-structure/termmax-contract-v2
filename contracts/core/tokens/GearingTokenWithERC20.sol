// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MathLib} from "../lib/MathLib.sol";
import "./AbstractGearingToken.sol";

/**
 * @title TermMax Gearing Token, using ERC20 token as collateral
 * @author Term Structure Labs
 */
contract GearingTokenWithERC20 is AbstractGearingToken {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using MathLib for *;

    /// @notice The operation failed because the collateral capacity is exceeded
    error CollateralCapacityExceeded();

    /// @notice The operation failed because the amount can not be uint256 max
    error AmountCanNotBeUint256Max();

    /// @notice The max capacity of collateral token
    uint256 public collateralCapacity;

    uint8 collateralDecimals;

    function __GearingToken_Implement_init(
        bytes memory initalParams
    ) internal override onlyInitializing {
        collateralCapacity = abi.decode(initalParams, (uint256));
        collateralDecimals = IERC20Metadata(_config.collateral).decimals();
    }

    function _updateConfig(bytes memory configData) internal virtual override {
        collateralCapacity = abi.decode(configData, (uint256));
    }

    function _checkBeforeMint(
        uint128,
        bytes memory collateralData
    ) internal virtual override {
        if (
            IERC20(_config.collateral).balanceOf(address(this)) +
                _decodeAmount(collateralData) >
            collateralCapacity
        ) {
            revert CollateralCapacityExceeded();
        }
    }

    function _delivery(
        uint256 proportion
    ) internal virtual override returns (bytes memory deliveryData) {
        uint collateralReserve = IERC20(_config.collateral).balanceOf(
            address(this)
        );
        uint amount = (collateralReserve * proportion) /
            Constants.DECIMAL_BASE_SQ;
        deliveryData = abi.encode(amount);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _mergeCollateral(
        bytes memory collateralDataA,
        bytes memory collateralDataB
    ) internal virtual override returns (bytes memory collateralData) {
        uint total = _decodeAmount(collateralDataA) +
            _decodeAmount(collateralDataB);
        collateralData = abi.encode(total);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _transferCollateralFrom(
        address from,
        address to,
        bytes memory collateralData
    ) internal virtual override {
        uint amount = _decodeAmount(collateralData);
        if (amount == 0) {
            return;
        }
        IERC20(_config.collateral).safeTransferFrom(from, to, amount);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _transferCollateral(
        address to,
        bytes memory collateralData
    ) internal virtual override {
        uint amount = _decodeAmount(collateralData);
        if (amount == 0) {
            return;
        }
        IERC20(_config.collateral).safeTransfer(to, amount);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _getCollateralValue(
        bytes memory collateralData,
        bytes memory priceData
    ) internal view virtual override returns (uint256) {
        uint collateralAmt = _decodeAmount(collateralData);
        (uint price, uint decimals, uint collateralDecimals) = abi.decode(
            priceData,
            (uint, uint, uint)
        );
        return
            (collateralAmt * price * Constants.DECIMAL_BASE) /
            (decimals * collateralDecimals);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _getCollateralPriceData(
        GtConfig memory config
    ) internal view virtual override returns (bytes memory priceData) {
        (uint256 price, uint8 decimals) = config.oracle.getPrice(
            config.collateral
        );
        uint priceDenominator = 10 ** decimals;

        uint cTokenDecimals = 10 ** collateralDecimals;
        priceData = abi.encode(price, priceDenominator, cTokenDecimals);
    }

    /// @notice Encode amount to collateral data
    function _decodeAmount(
        bytes memory collateralData
    ) internal pure returns (uint256 amount) {
        amount = abi.decode(collateralData, (uint));
        if (amount == type(uint256).max) {
            revert AmountCanNotBeUint256Max();
        }
    }

    /// @notice Decode amount from collateral data
    function _encodeAmount(
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(amount);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _removeCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual override returns (bytes memory) {
        uint amount = _decodeAmount(loan.collateralData) -
            _decodeAmount(collateralData);
        return _encodeAmount(amount);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _addCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual override returns (bytes memory) {
        uint amount = _decodeAmount(loan.collateralData) +
            _decodeAmount(collateralData);
        return _encodeAmount(amount);
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _calcLiquidationResult(
        LoanInfo memory loan,
        uint128 repayAmt,
        ValueAndPrice memory valueAndPrice
    )
        internal
        virtual
        override
        returns (
            bytes memory cToLiquidator,
            bytes memory cToTreasurer,
            bytes memory remainningC
        )
    {
        uint collateralAmt = _decodeAmount(loan.collateralData);

        (
            uint collateralPrice,
            uint collateralPriceDecimals,
            uint collateralDecimals
        ) = abi.decode(valueAndPrice.collateralPriceData, (uint, uint, uint));

        // maxRomvedCollateral = min(
        // (repayAmt * (1 + REWARD_TO_LIQUIDATOR + REWARD_TO_PROTOCOL)) * debtTokenPrice / collateralTokenPrice ,
        // collateralAmt *(repayAmt / debtAmt)
        // )

        /* DP := debt token price (valueAndPrice.underlyingPrice)
         * DPD := debt token price decimal (valueAndPrice.priceDenominator)
         * CP := collateral token price (collateralPrice)
         * CPD := collateral token price decimal (collateralPriceDecimals)
         * The value of 1(decimal) debt token / The value of 1(decimal) collateral token
         *     ddPriceToCdPrice = (DP/DPD) / (CP/CPD) = (DP*CPD) / (CP*DPD)
         */
        uint ddPriceToCdPrice = (valueAndPrice.underlyingPrice *
            collateralPriceDecimals *
            Constants.DECIMAL_BASE) /
            (collateralPrice * valueAndPrice.priceDenominator);

        // calculate the amount of collateral that is equivalent to repayAmt
        // with debt to collateral price
        uint cEqualRepayAmt = (repayAmt *
            ddPriceToCdPrice *
            collateralDecimals) /
            (valueAndPrice.underlyingDenominator * Constants.DECIMAL_BASE);

        uint rewardToLiquidator = (cEqualRepayAmt *
            GearingTokenConstants.REWARD_TO_LIQUIDATOR) /
            Constants.DECIMAL_BASE;
        uint rewardToProtocol = (cEqualRepayAmt *
            GearingTokenConstants.REWARD_TO_PROTOCOL) / Constants.DECIMAL_BASE;

        uint removedCollateralAmt = cEqualRepayAmt +
            rewardToLiquidator +
            rewardToProtocol;

        removedCollateralAmt = removedCollateralAmt.min(
            (collateralAmt * repayAmt) / loan.debtAmt
        );

        // Case 1: removed collateral can not cover repayAmt + rewardToLiquidator
        if (removedCollateralAmt <= cEqualRepayAmt + rewardToLiquidator) {
            cToLiquidator = _encodeAmount(removedCollateralAmt);
            cToTreasurer = _encodeAmount(0);
            remainningC = _encodeAmount(0);
        }
        // Case 2: removed collateral can cover repayAmt + rewardToLiquidator but not rewardToProtocol
        else if (
            removedCollateralAmt <
            cEqualRepayAmt + rewardToLiquidator + rewardToProtocol
        ) {
            cToLiquidator = _encodeAmount(cEqualRepayAmt + rewardToLiquidator);
            cToTreasurer = _encodeAmount(
                removedCollateralAmt - cEqualRepayAmt - rewardToLiquidator
            );
            remainningC = _encodeAmount(0);
        }
        // Case 3: removed collateral equal repayAmt + rewardToLiquidator + rewardToProtocol
        else {
            cToLiquidator = _encodeAmount(cEqualRepayAmt + rewardToLiquidator);
            cToTreasurer = _encodeAmount(rewardToProtocol);
        }
        // Calculate remainning collateral
        remainningC = _encodeAmount(collateralAmt - removedCollateralAmt);
    }
}
