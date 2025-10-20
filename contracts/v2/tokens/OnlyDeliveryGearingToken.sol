// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "./AbstractGearingTokenV2.sol";

/**
 * @title TermMax Gearing Token, only support delivery, can not remove collateral
 *        after mint unless repay all debt
 * @author Term Structure Labs
 */
contract OnlyDeliveryGearingToken is AbstractGearingTokenV2 {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IERC20Metadata;
    using Math for *;

    uint256 constant UINT256_LENGTH = 32;

    /// @notice The max capacity of collateral token
    uint256 public collateralCapacity;

    uint256 private collateralDenominator;

    constructor() {
        _disableInitializers();
    }

    function __GearingToken_Implement_init(bytes memory initialParams) internal override onlyInitializing {
        if (_config.loanConfig.liquidatable) {
            revert GtDoNotSupportLiquidation();
        }
        _updateConfig(initialParams);
        collateralDenominator = 10 ** IERC20Metadata(_config.collateral).decimals();
    }

    function _updateConfig(bytes memory configData) internal virtual override {
        collateralCapacity = abi.decode(configData, (uint256));
        emit GearingTokenEventsV2.CollateralCapacityUpdated(collateralCapacity);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function flashRepay(
        uint256 id,
        uint128 repayAmt,
        bool byDebtToken,
        bytes memory removedCollateral,
        bytes calldata callbackData
    ) external virtual override nonReentrant isOwnerOrDelegate(id, msg.sender) returns (bool) {
        LoanInfo memory loan = loanMapping[id];
        require(
            repayAmt == loan.debtAmt && keccak256(removedCollateral) == keccak256(loan.collateralData),
            GearingTokenErrorsV2.OnlyFullRepaySupported()
        );
        return _flashRepay(id, repayAmt, byDebtToken, removedCollateral, callbackData);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function repayAndRemoveCollateral(
        uint256 id,
        uint128 repayAmt,
        bool byDebtToken,
        address collateralRecipient,
        bytes memory removedCollateral
    )
        external
        virtual
        override
        nonReentrant
        isOwnerOrDelegate(id, msg.sender)
        returns (bool repayAll, uint128 finalRepayAmt)
    {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
        }
        LoanInfo memory loan;
        (loan, repayAll, finalRepayAmt) = _repay(id, repayAmt);
        if (loan.debtAmt != 0) {
            revert GearingTokenErrorsV2.OnlyFullRepaySupported();
        }
        loan.collateralData = _removeCollateral(loan, removedCollateral);
        loanMapping[id] = loan;
        // Transfer collateral to the recipient
        _transferCollateral(collateralRecipient, removedCollateral);
        // Transfer debt/ft tokens from caller to market
        if (byDebtToken) {
            config.debtToken.safeTransferFrom(msg.sender, marketAddr(), finalRepayAmt);
        } else {
            config.ft.safeTransferFrom(msg.sender, marketAddr(), finalRepayAmt);
        }
        emit GearingTokenEventsV2.RepayAndRemoveCollateral(id, finalRepayAmt, byDebtToken, removedCollateral);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function augmentDebt(address caller, uint256 id, uint256 ftAmt)
        external
        virtual
        override
        nonReentrant
        onlyOwner
        isOwnerOrDelegate(id, caller)
    {
        revert GearingTokenErrorsV2.CannotAugmentDebtOnOnlyDeliveryGt();
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function removeCollateral(uint256 id, bytes memory collateralData)
        external
        virtual
        override
        nonReentrant
        isOwnerOrDelegate(id, msg.sender)
    {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
        }

        LoanInfo memory loan = loanMapping[id];
        if (loan.debtAmt != 0) {
            revert GearingTokenErrorsV2.CannotRemoveCollateralWithDebt();
        }
        loan.collateralData = _removeCollateral(loan, collateralData);
        loanMapping[id] = loan;

        // Transfer collateral to the owner or delegator
        _transferCollateral(msg.sender, collateralData);

        emit RemoveCollateral(id, loan.collateralData);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function getLiquidationInfo(uint256 id)
        external
        view
        virtual
        override
        returns (bool isLiquidable, uint128 ltv, uint128 maxRepayAmt)
    {
        (,, ltv,) = _getLiquidationInfo(loanMapping[id], _config);
    }

    /**
     * @inheritdoc AbstractGearingTokenV2
     */
    function liquidate(uint256 id, uint128 repayAmt, bool byDebtToken) external virtual override nonReentrant {
        revert GtDoNotSupportLiquidation();
    }

    function _checkBeforeMint(uint128, bytes memory collateralData) internal virtual override {
        if (collateralData.length > UINT256_LENGTH) {
            revert GearingTokenErrorsV2.InvalidCollateralData();
        }
        if (IERC20(_config.collateral).balanceOf(address(this)) + _decodeAmount(collateralData) > collateralCapacity) {
            revert GearingTokenErrorsV2.CollateralCapacityExceeded();
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
        (uint256 price, uint256 priceDenominator, uint256 collateralDenominator) =
            abi.decode(priceData, (uint256, uint256, uint256));
        return collateralAmt.mulDiv(price * Constants.DECIMAL_BASE, priceDenominator * collateralDenominator);
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

    /// @notice Decode amount from collateral data
    function _decodeAmount(bytes memory collateralData) internal pure returns (uint256 amount) {
        amount = abi.decode(collateralData, (uint256));
    }

    /// @notice Encode amount to collateral data
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
        revert GtDoNotSupportLiquidation();
    }
}
