// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./AbstractGearingToken.sol";

/**
 * @title Term Max Gearing Token, using ERC20 token as collateral
 * @author Term Structure Labs
 */
contract GearingTokenWithERC20 is AbstractGearingToken {
    using SafeCast for uint256;
    using SafeCast for int256;

    struct GearingTokenWithERC20Storage {
        /// @notice The oracle of collateral in USD
        AggregatorV3Interface collateralOracle;
    }

    bytes32 internal constant STORAGE_SLOT_GEARING_TOKEN_ERC20_STORAGE =
        bytes32(
            uint256(keccak256("TermMax.storage.GearingTokenWithERC20Storage")) -
                1
        );

    function _getGearingTokenWithERC20Storage()
        private
        pure
        returns (GearingTokenWithERC20Storage storage s)
    {
        bytes32 slot = STORAGE_SLOT_GEARING_TOKEN_ERC20_STORAGE;
        assembly {
            s.slot := slot
        }
    }

    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        GtConfig memory config,
        AggregatorV3Interface collateralOracle
    ) public initializer {
        __AbstractGearingToken_init(name, symbol, admin, config);
        _getGearingTokenWithERC20Storage().collateralOracle = collateralOracle;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function delivery(
        uint256 proportion,
        address to
    )
        external
        override
        onlyOwner
        nonReentrant
        returns (bytes memory deliveryData)
    {
        IERC20 collateral = IERC20(_getGearingTokenStorage().config.collateral);
        uint collateralReserve = collateral.balanceOf(address(this));
        uint amount = (collateralReserve * proportion) / Constants.DECIMAL_BASE;
        collateral.transfer(to, amount);
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
        IERC20(_getGearingTokenStorage().config.collateral).transferFrom(
            from,
            to,
            _decodeAmount(collateralData)
        );
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _transferCollateral(
        address to,
        bytes memory collateralData
    ) internal virtual override {
        IERC20(_getGearingTokenStorage().config.collateral).transfer(
            to,
            _decodeAmount(collateralData)
        );
    }

    /**
     * @inheritdoc AbstractGearingToken
     */
    function _getCollateralValue(
        bytes memory collateralData,
        bytes memory priceData
    ) internal view virtual override returns (uint256) {
        uint collateralAmt = _decodeAmount(collateralData);
        (uint price, uint decimals, uint cTokenDecimals) = abi.decode(
            priceData,
            (uint, uint, uint)
        );
        return (collateralAmt * price) / (decimals * cTokenDecimals);
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
        AggregatorV3Interface collateralOracle = _getGearingTokenWithERC20Storage()
                .collateralOracle;
        uint decimals = 10 ** collateralOracle.decimals();
        (, int256 answer, , , ) = collateralOracle.latestRoundData();
        uint price = answer.toUint256();
        uint cTokenDecimals = 10 **
            IERC20Metadata(_getGearingTokenStorage().config.collateral)
                .decimals();
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

        (uint256 collateralPrice, uint256 collateralPriceDecimals) = abi.decode(
            valueAndPrice.collateralPriceData,
            (uint, uint)
        );

        // MaxRomvedCollateral = min(
        // (repayAmt * (1 + REWARD_TO_LIQUIDATOR + REWARD_TO_PROTOCOL)) * underlyingPrice / collateralPrice
        // , collateralAmt *(repayAmt / debtAmt)
        // )
        uint uPriceToCPrice = (valueAndPrice.underlyingPrice *
            Constants.DECIMAL_BASE *
            collateralPriceDecimals) /
            (valueAndPrice.priceDecimals * collateralPrice);

        uint cEqualRepayAmt = (repayAmt * Constants.DECIMAL_BASE) /
            uPriceToCPrice;
        uint rewardToLiquidator = (repayAmt * REWARD_TO_LIQUIDATOR) /
            uPriceToCPrice;
        uint rewardToProtocol = (repayAmt * REWARD_TO_PROTOCOL) /
            uPriceToCPrice;

        uint removedCollateralAmt = cEqualRepayAmt +
            rewardToLiquidator +
            rewardToProtocol;

        removedCollateralAmt = _min(
            removedCollateralAmt,
            (collateralAmt * repayAmt) / loan.debtAmt
        );
        // Case 1: removed collateral can not cover repayAmt + rewardToLiquidator
        if (removedCollateralAmt <= cEqualRepayAmt + rewardToLiquidator) {
            cToLiquidator = _encodeAmount(removedCollateralAmt);
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
        }
        // Case 3: removed collateral equal repayAmt + rewardToLiquidator + rewardToProtocol
        else {
            cToLiquidator = _encodeAmount(cEqualRepayAmt + rewardToLiquidator);
            cToTreasurer = _encodeAmount(rewardToProtocol);
        }
        // Calculate remainning collateral
        if (collateralAmt > removedCollateralAmt) {
            remainningC = _encodeAmount(collateralAmt - removedCollateralAmt);
        }
    }

    /// @notice Returns the smaller of two values
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
