// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./AbstractGearingTokenV2.sol";

/**
 * @title TermMax Gearing Token, using ERC20 token as collateral
 * @author Term Structure Labs
 */
contract GearingTokenWithERC20V2 is AbstractGearingTokenV2 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IERC20Metadata;
    using Math for *;

    /// @notice The operation failed because the collateral capacity is exceeded
    error CollateralCapacityExceeded();

    /// @notice The operation failed because the amount can not be uint256 max
    error AmountCanNotBeUint256Max();

    /// @notice Emitted when the collateral capacity is updated
    event CollateralCapacityUpdated(uint256 newCapacity);

    /// @notice The max capacity of collateral token
    uint256 public collateralCapacity;

    uint256 private collateralDenominator;

    constructor() {
        _disableInitializers();
    }

    function __GearingToken_Implement_init(bytes memory initalParams) internal override onlyInitializing {
        _updateConfig(initalParams);
        collateralDenominator = 10 ** IERC20Metadata(_config.collateral).decimals();
    }

    function _updateConfig(bytes memory configData) internal virtual override {
        collateralCapacity = abi.decode(configData, (uint256));
        emit CollateralCapacityUpdated(collateralCapacity);
    }

    function _checkBeforeMint(uint128, bytes memory collateralData) internal virtual override {
        if (IERC20(_config.collateral).balanceOf(address(this)) + _decodeAmount(collateralData) > collateralCapacity) {
            revert CollateralCapacityExceeded();
        }
    }

    function _delivery(uint256 proportion) internal view virtual override returns (bytes memory deliveryData) {
        uint256 collateralReserve = IERC20(_config.collateral).balanceOf(address(this));
        uint256 amount = collateralReserve.mulDiv(proportion, Constants.DECIMAL_BASE_SQ);
        deliveryData = abi.encode(amount);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _mergeCollateral(bytes memory collateralDataA, bytes memory collateralDataB)
        internal
        virtual
        override
        returns (bytes memory collateralData)
    {
        uint256 total = _decodeAmount(collateralDataA) + _decodeAmount(collateralDataB);
        collateralData = abi.encode(total);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _transferCollateralFrom(address from, address to, bytes memory collateralData) internal virtual override {
        uint256 amount = _decodeAmount(collateralData);
        if (amount != 0) {
            IERC20(_config.collateral).safeTransferFrom(from, to, amount);
        }
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _transferCollateral(address to, bytes memory collateralData) internal virtual override {
        uint256 amount = _decodeAmount(collateralData);
        if (amount != 0) {
            IERC20(_config.collateral).safeTransfer(to, amount);
        }
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _getCollateralValue(bytes memory collateralData, bytes memory priceData)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        uint256 collateralAmt = _decodeAmount(collateralData);
        (uint256 price, uint256 priceDenominator, uint256 collateralDemonimator) =
            abi.decode(priceData, (uint256, uint256, uint256));
        return collateralAmt.mulDiv(price * Constants.DECIMAL_BASE, priceDenominator * collateralDemonimator);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _getCollateralPriceData(GtConfig memory config)
        internal
        view
        virtual
        override
        returns (bytes memory priceData)
    {
        (uint256 price, uint8 decimals) = config.loanConfig.oracle.getPrice(config.collateral);
        uint256 priceDenominator = 10 ** decimals;

        priceData = abi.encode(price, priceDenominator, collateralDenominator);
    }

    /// @notice Encode amount to collateral data
    function _decodeAmount(bytes memory collateralData) internal pure returns (uint256 amount) {
        amount = abi.decode(collateralData, (uint256));
        if (amount == type(uint256).max) {
            revert AmountCanNotBeUint256Max();
        }
    }

    /// @notice Decode amount from collateral data
    function _encodeAmount(uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(amount);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _removeCollateral(LoanInfo memory loan, bytes memory collateralData)
        internal
        virtual
        override
        returns (bytes memory)
    {
        uint256 amount = _decodeAmount(loan.collateralData) - _decodeAmount(collateralData);
        return _encodeAmount(amount);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _addCollateral(LoanInfo memory loan, bytes memory collateralData)
        internal
        virtual
        override
        returns (bytes memory)
    {
        uint256 amount = _decodeAmount(loan.collateralData) + _decodeAmount(collateralData);
        return _encodeAmount(amount);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function _calcLiquidationResult(LoanInfo memory loan, uint128 repayAmt, ValueAndPrice memory valueAndPrice)
        internal
        virtual
        override
        returns (bytes memory, bytes memory, bytes memory)
    {
        uint256 collateralAmt = _decodeAmount(loan.collateralData);

        uint256 removedCollateralAmt;
        uint256 cEqualRepayAmt;
        uint256 rewardToLiquidator;
        uint256 rewardToProtocol;

        if (loan.debtAmt != 0) {
            (uint256 collateralPrice, uint256 cPriceDenominator, uint256 cTokenDenominator) =
                abi.decode(valueAndPrice.collateralPriceData, (uint256, uint256, uint256));

            /* DP := debt token price (valueAndPrice.debtPrice)
             * DPD := debt token price decimal (valueAndPrice.priceDenominator)
             * CP := collateral token price (collateralPrice)
             * CPD := collateral token price decimal (cPriceDenominator)
             * liquidate value = repayAmt * DP / debt token decimals
             * collateral amount to remove = liquidate value * collateral decimals * cpd / (CP * DPD)
             */
            uint256 liquidateValueInPriceScale = repayAmt.mulDiv(valueAndPrice.debtPrice, valueAndPrice.debtDenominator);

            cEqualRepayAmt = liquidateValueInPriceScale.mulDiv(
                cPriceDenominator * cTokenDenominator, collateralPrice * valueAndPrice.priceDenominator
            );

            rewardToLiquidator =
                cEqualRepayAmt.mulDiv(GearingTokenConstants.REWARD_TO_LIQUIDATOR, Constants.DECIMAL_BASE);
            rewardToProtocol = cEqualRepayAmt.mulDiv(GearingTokenConstants.REWARD_TO_PROTOCOL, Constants.DECIMAL_BASE);

            removedCollateralAmt = cEqualRepayAmt + rewardToLiquidator + rewardToProtocol;
            removedCollateralAmt = removedCollateralAmt.min(collateralAmt.mulDiv(repayAmt, loan.debtAmt));
        }
        uint256 cToLiquidatorAmount = removedCollateralAmt.min(cEqualRepayAmt + rewardToLiquidator);
        removedCollateralAmt -= cToLiquidatorAmount;
        uint256 cToTreasurerAmount = removedCollateralAmt.min(rewardToProtocol);
        uint256 remainingCollateralAmt = collateralAmt - cToLiquidatorAmount - cToTreasurerAmount;
        return (abi.encode(cToLiquidatorAmount), abi.encode(cToTreasurerAmount), abi.encode(remainingCollateralAmt));
    }
}
