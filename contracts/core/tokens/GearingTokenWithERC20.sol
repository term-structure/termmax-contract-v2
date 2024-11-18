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
    using MathLib for *;

    /// @notice The oracle of collateral in USD
    AggregatorV3Interface public collateralOracle;

    function __GearingToken_Implement_init(
        bytes memory initalParams
    ) internal override onlyInitializing {
        collateralOracle = AggregatorV3Interface(
            abi.decode(initalParams, (address))
        );
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
        IERC20(_config.collateral).transferFrom(from, to, amount);
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
        IERC20(_config.collateral).transfer(to, amount);
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
    function _getCollateralPriceData()
        internal
        view
        virtual
        override
        returns (bytes memory priceData)
    {
        uint decimals = 10 ** collateralOracle.decimals();
        (, int256 answer, , , ) = collateralOracle.latestRoundData();
        uint price = answer.toUint256();
        uint cTokenDecimals = 10 **
            IERC20Metadata(_config.collateral).decimals();
        priceData = abi.encode(price, decimals, cTokenDecimals);
    }

    /// @notice Encode amount to collateral data
    function _decodeAmount(
        bytes memory collateralData
    ) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint));
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
         * DPD := debt token price decimal (valueAndPrice.priceDecimals)
         * CP := collateral token price (collateralPrice)
         * CPD := collateral token price decimal (collateralPriceDecimals)
         * The value of 1(decimal) debt token / The value of 1(decimal) collateral token
         *     ddPriceToCdPrice = (DP/DPD) / (CP/CPD) = (DP*CPD) / (CP*DPD)
         */
        uint ddPriceToCdPrice = (valueAndPrice.underlyingPrice *
            collateralPriceDecimals *
            Constants.DECIMAL_BASE) /
            (collateralPrice * valueAndPrice.priceDecimals);

        // calculate the amount of collateral that is equivalent to repayAmt
        // with debt to collateral price
        uint cEqualRepayAmt = (repayAmt *
            ddPriceToCdPrice *
            collateralDecimals) /
            (valueAndPrice.underlyingDecimals * Constants.DECIMAL_BASE);

        uint rewardToLiquidator = (cEqualRepayAmt * REWARD_TO_LIQUIDATOR) /
            Constants.DECIMAL_BASE;
        uint rewardToProtocol = (cEqualRepayAmt * REWARD_TO_PROTOCOL) /
            Constants.DECIMAL_BASE;

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
