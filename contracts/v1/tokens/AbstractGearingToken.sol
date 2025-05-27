// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "../lib/Constants.sol";
import {GearingTokenConstants} from "../lib/GearingTokenConstants.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";
import {IFlashRepayer} from "./IFlashRepayer.sol";
import {IGearingToken, IERC20Metadata, IERC20} from "./IGearingToken.sol";
import {GearingTokenErrors} from "../errors/GearingTokenErrors.sol";
import {GearingTokenEvents} from "../events/GearingTokenEvents.sol";
import {GtConfig, IOracle} from "../storage/TermMaxStorage.sol";

/**
 * @title TermMax Gearing Token
 * @author Term Structure Labs
 */
abstract contract AbstractGearingToken is
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    IGearingToken,
    GearingTokenErrors,
    GearingTokenEvents
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IERC20Metadata;

    struct LoanInfo {
        /// @notice Debt amount in debtToken token
        uint128 debtAmt;
        /// @notice Encoded collateral data
        bytes collateralData;
    }

    struct ValueAndPrice {
        /// @notice USD value of collateral
        uint256 collateralValue;
        /// @notice USD value of debt with price and token decimals
        uint256 debtValueWithDecimals;
        /// @notice USD price of debt token
        uint256 debtPrice;
        /// @notice Denominator of USD price
        uint256 priceDenominator;
        /// @notice Denominator of debt token
        uint256 debtDenominator;
        /// @notice Encoded USD price of collateral token
        bytes collateralPriceData;
    }

    /// @notice Configuturation of Gearing Token
    GtConfig _config;
    /// @notice Total supply of Gearing Token
    uint256 total;
    /// @notice Mapping relationship between Gearing Token id and loan
    mapping(uint256 => LoanInfo) loanMapping;

    uint8 debtDecimals;

    /**
     * @inheritdoc IGearingToken
     */
    function initialize(string memory name, string memory symbol, GtConfig memory config_, bytes memory initalParams)
        external
        override
        initializer
    {
        __AbstractGearingToken_init(name, symbol, config_);
        __GearingToken_Implement_init(initalParams);
    }

    function __AbstractGearingToken_init(string memory name, string memory symbol, GtConfig memory config_)
        internal
        onlyInitializing
    {
        if (config_.loanConfig.liquidationLtv <= config_.loanConfig.maxLtv) {
            revert LiquidationLtvMustBeGreaterThanMaxLtv();
        }
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);
        _config = config_;
        debtDecimals = _config.debtToken.decimals();
    }

    function __GearingToken_Implement_init(bytes memory initalParams) internal virtual;

    /**
     * @inheritdoc IGearingToken
     */
    function setTreasurer(address treasurer) external onlyOwner {
        _config.treasurer = treasurer;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function updateConfig(bytes memory configData) external onlyOwner {
        _updateConfig(configData);
        emit UpdateConfig(configData);
    }

    function _updateConfig(bytes memory configData) internal virtual;

    /**
     * @inheritdoc IGearingToken
     */
    function getGtConfig() external view override returns (GtConfig memory) {
        return _config;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function marketAddr() public view override returns (address) {
        return owner();
    }

    /**
     * @inheritdoc IGearingToken
     */
    function liquidatable() external view returns (bool) {
        return _config.loanConfig.liquidatable;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function mint(address collateralProvider, address to, uint128 debtAmt, bytes memory collateralData)
        external
        override
        nonReentrant
        onlyOwner
        returns (uint256 id)
    {
        _checkBeforeMint(debtAmt, collateralData);
        _transferCollateralFrom(collateralProvider, address(this), collateralData);
        id = _mintInternal(to, debtAmt, collateralData, _config);
    }

    /// @notice Check if the loan can be minted
    function _checkBeforeMint(uint128 debtAmt, bytes memory collateralData) internal virtual;

    function _mintInternal(address to, uint128 debtAmt, bytes memory collateralData, GtConfig memory config)
        internal
        returns (uint256 id)
    {
        LoanInfo memory loan = LoanInfo(debtAmt, collateralData);
        ValueAndPrice memory valueAndPrice = _getValueAndPrice(config, loan);
        uint128 ltv = _calculateLtv(valueAndPrice);
        if (ltv > config.loanConfig.maxLtv) {
            revert GtIsNotHealthy(0, to, ltv);
        }
        id = ++total;
        loanMapping[id] = loan;
        _mint(to, id);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function augmentDebt(address caller, uint256 id, uint256 ftAmt) external override nonReentrant onlyOwner {
        if (caller != ownerOf(id) && caller != getApproved(id)) {
            revert AuthorizationFailed(id, caller);
        }
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }

        LoanInfo memory loan = loanMapping[id];
        loan.debtAmt += ftAmt.toUint128();

        ValueAndPrice memory valueAndPrice = _getValueAndPrice(config, loan);
        uint128 ltv = _calculateLtv(valueAndPrice);
        if (ltv > config.loanConfig.maxLtv) {
            revert GtIsNotHealthy(id, msg.sender, ltv);
        }
        loanMapping[id] = loan;

        emit AugmentDebt(id, ftAmt);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function loanInfo(uint256 id)
        external
        view
        override
        returns (address owner, uint128 debtAmt, bytes memory collateralData)
    {
        owner = ownerOf(id);
        LoanInfo memory loan = loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
    }

    function _burnInternal(uint256 id) internal {
        _burn(id);
        delete loanMapping[id];
    }

    /**
     * @inheritdoc IGearingToken
     */
    function merge(uint256[] memory ids) external nonReentrant returns (uint256 newId) {
        uint128 totalDebtAmt;
        bytes memory mergedCollateralData;
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            LoanInfo memory loan = loanMapping[id];
            address owner = ownerOf(id);
            if (msg.sender != owner) {
                revert CanNotMergeLoanWithDiffOwner(id, owner);
            }
            totalDebtAmt += loan.debtAmt;
            mergedCollateralData =
                i == 0 ? loan.collateralData : _mergeCollateral(mergedCollateralData, loan.collateralData);
            _burnInternal(id);
        }
        newId = _mintInternal(msg.sender, totalDebtAmt, mergedCollateralData, _config);
        emit MergeGts(msg.sender, newId, ids);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function repay(uint256 id, uint128 repayAmt, bool byDebtToken) external override nonReentrant {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }

        if (byDebtToken) {
            config.debtToken.safeTransferFrom(msg.sender, marketAddr(), repayAmt);
        } else {
            // Those ft tokens have been approved to market and will be burn after maturity
            config.ft.safeTransferFrom(msg.sender, marketAddr(), repayAmt);
        }
        _repay(id, repayAmt);
        emit Repay(id, repayAmt, byDebtToken);
    }

    function flashRepay(uint256 id, bool byDebtToken, bytes calldata callbackData) external override nonReentrant {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }
        LoanInfo memory loan = loanMapping[id];
        if (ownerOf(id) != msg.sender) {
            revert CallerIsNotTheOwner(id);
        }
        // Transfer collateral to the owner
        _transferCollateral(msg.sender, loan.collateralData);
        IERC20 repayToken = byDebtToken ? config.debtToken : config.ft;

        IFlashRepayer(msg.sender).executeOperation(
            repayToken, loan.debtAmt, config.collateral, loan.collateralData, callbackData
        );
        repayToken.safeTransferFrom(msg.sender, owner(), loan.debtAmt);
        _burnInternal(id);
        emit Repay(id, loan.debtAmt, byDebtToken);
    }

    function _repay(uint256 id, uint128 repayAmt) internal {
        LoanInfo memory loan = loanMapping[id];
        if (repayAmt > loan.debtAmt) {
            revert RepayAmtExceedsMaxRepayAmt(id, repayAmt, loan.debtAmt);
        }
        if (repayAmt == loan.debtAmt) {
            address gtOwner = ownerOf(id);
            // Burn this nft
            _burnInternal(id);
            _transferCollateral(gtOwner, loan.collateralData);
        } else {
            uint128 debtAmt = loan.debtAmt - repayAmt;
            loanMapping[id].debtAmt = debtAmt;
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function removeCollateral(uint256 id, bytes memory collateralData) external override nonReentrant {
        if (msg.sender != ownerOf(id)) {
            revert CallerIsNotTheOwner(id);
        }

        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }

        LoanInfo memory loan = loanMapping[id];
        loan.collateralData = _removeCollateral(loan, collateralData);

        _transferCollateral(msg.sender, collateralData);

        ValueAndPrice memory valueAndPrice = _getValueAndPrice(config, loan);
        uint128 ltv = _calculateLtv(valueAndPrice);
        if (ltv > config.loanConfig.maxLtv) {
            revert GtIsNotHealthy(id, msg.sender, ltv);
        }
        loanMapping[id] = loan;

        emit RemoveCollateral(id, loan.collateralData);
    }

    function _removeCollateral(LoanInfo memory loan, bytes memory collateralData)
        internal
        virtual
        returns (bytes memory);

    /**
     * @inheritdoc IGearingToken
     */
    function addCollateral(uint256 id, bytes memory collateralData) external override nonReentrant {
        if (_config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }
        LoanInfo memory loan = loanMapping[id];

        _transferCollateralFrom(msg.sender, address(this), collateralData);
        loan.collateralData = _addCollateral(loan, collateralData);
        loanMapping[id] = loan;
        emit AddCollateral(id, loan.collateralData);
    }

    function _addCollateral(LoanInfo memory loan, bytes memory collateralData)
        internal
        virtual
        returns (bytes memory);

    /**
     * @inheritdoc IGearingToken
     */
    function getLiquidationInfo(uint256 id)
        external
        view
        returns (bool isLiquidable, uint128 ltv, uint128 maxRepayAmt)
    {
        LoanInfo memory loan = loanMapping[id];
        GtConfig memory config = _config;
        (isLiquidable, maxRepayAmt, ltv,) = _getLiquidationInfo(loan, config);
    }

    function _getLiquidationInfo(LoanInfo memory loan, GtConfig memory config)
        internal
        view
        returns (bool isLiquidable, uint128 maxRepayAmt, uint128 ltv, ValueAndPrice memory valueAndPrice)
    {
        valueAndPrice = _getValueAndPrice(config, loan);
        ltv = _calculateLtv(valueAndPrice);

        if (config.loanConfig.liquidatable) {
            // Liquidation cases:
            // t >= m + w => F, "No liquidation after maturity plus liquidation window
            // t >= m && t < m + w => T, "Liquidation allowed during liquidation window"
            // t < m => ltv >= lltv => T, "Liquidation only allowed before maturity if ltv >= lltv"

            if (block.timestamp >= config.maturity + Constants.LIQUIDATION_WINDOW) {
                isLiquidable = false;
            } else if (block.timestamp >= config.maturity) {
                isLiquidable = true;
                maxRepayAmt = loan.debtAmt;
            } else if (ltv >= config.loanConfig.liquidationLtv) {
                isLiquidable = true;
                // collateralValue(price decimals) and HALF_LIQUIDATION_THRESHOLD(base decimals 1e8)
                maxRepayAmt = (valueAndPrice.collateralValue * Constants.DECIMAL_BASE) / valueAndPrice.priceDenominator
                    < GearingTokenConstants.HALF_LIQUIDATION_THRESHOLD ? loan.debtAmt : loan.debtAmt / 2;
            }
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function liquidate(uint256 id, uint128 repayAmt, bool byDebtToken) external override nonReentrant {
        LoanInfo memory loan = loanMapping[id];
        GtConfig memory config = _config;
        if (!config.loanConfig.liquidatable) {
            revert GtDoNotSupportLiquidation();
        }
        (bool isLiquidable, uint128 maxRepayAmt, uint128 ltvBefore, ValueAndPrice memory valueAndPrice) =
            _getLiquidationInfo(loan, config);

        if (!isLiquidable) {
            uint256 liquidationDeadline = config.maturity + Constants.LIQUIDATION_WINDOW;
            if (block.timestamp >= liquidationDeadline) {
                revert CanNotLiquidationAfterFinalDeadline(id, liquidationDeadline);
            }
            revert GtIsSafe(id);
        }
        if (repayAmt > maxRepayAmt) {
            revert RepayAmtExceedsMaxRepayAmt(id, repayAmt, maxRepayAmt);
        }
        // Transfer token
        if (byDebtToken) {
            config.debtToken.safeTransferFrom(msg.sender, marketAddr(), repayAmt);
        } else {
            config.ft.safeTransferFrom(msg.sender, marketAddr(), repayAmt);
        }

        // Do liquidate
        (bytes memory cToLiquidator, bytes memory cToTreasurer, bytes memory remainningC) =
            _calcLiquidationResult(loan, repayAmt, valueAndPrice);

        if (repayAmt == loan.debtAmt) {
            if (remainningC.length > 0) {
                _transferCollateral(ownerOf(id), remainningC);
            }
            // update storage
            _burnInternal(id);
        } else {
            loan.debtAmt -= repayAmt;
            loan.collateralData = remainningC;

            // Check ltv after partial liquidation
            {
                valueAndPrice.collateralValue = _getCollateralValue(remainningC, valueAndPrice.collateralPriceData);
                valueAndPrice.debtValueWithDecimals =
                    (loan.debtAmt * valueAndPrice.debtPrice) / valueAndPrice.debtDenominator;
                uint128 ltvAfter = _calculateLtv(valueAndPrice);
                if (ltvBefore < ltvAfter) {
                    revert LtvIncreasedAfterLiquidation(id, ltvBefore, ltvAfter);
                }
            }
            // update storage
            loanMapping[id] = loan;
        }
        // Transfer collateral
        if (cToTreasurer.length > 0) {
            _transferCollateral(config.treasurer, cToTreasurer);
        }
        _transferCollateral(msg.sender, cToLiquidator);

        emit Liquidate(id, msg.sender, repayAmt, byDebtToken, cToLiquidator, cToTreasurer, remainningC);
    }

    /// @notice Return the collateral distribution plan after liquidation
    /// @param loan The loan data, contains debt amount and collateral data
    /// @param repayAmt The amount of the debt to be liquidate
    /// @param valueAndPrice Debt and collateral prices, values
    /// @return cToLiquidator Collateral data assigned to liquidator
    /// @return cToTreasurer Collateral data assigned to protocol
    /// @return remainningC Remainning collateral data, will assigned to debt's owner
    ///                     if the debt is fully liquidated.
    function _calcLiquidationResult(LoanInfo memory loan, uint128 repayAmt, ValueAndPrice memory valueAndPrice)
        internal
        virtual
        returns (bytes memory cToLiquidator, bytes memory cToTreasurer, bytes memory remainningC);

    /**
     * @inheritdoc IGearingToken
     */
    function getCollateralValue(bytes memory collateralData) external view override returns (uint256 collateralValue) {
        bytes memory priceData = _getCollateralPriceData(_config);
        return _getCollateralValue(collateralData, priceData);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function previewDelivery(uint256 proportion) external view override returns (bytes memory deliveryData) {
        deliveryData = _delivery(proportion);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function delivery(uint256 proportion, address to)
        external
        override
        nonReentrant
        onlyOwner
        returns (bytes memory deliveryData)
    {
        deliveryData = _delivery(proportion);
        _transferCollateral(to, deliveryData);
    }

    function _delivery(uint256 proportion) internal view virtual returns (bytes memory deliveryData);

    function _getValueAndPrice(GtConfig memory config, LoanInfo memory loan)
        internal
        view
        returns (ValueAndPrice memory valueAndPrice)
    {
        valueAndPrice.collateralPriceData = _getCollateralPriceData(config);
        valueAndPrice.collateralValue = _getCollateralValue(loan.collateralData, valueAndPrice.collateralPriceData);

        uint8 priceDecimals;
        (valueAndPrice.debtPrice, priceDecimals) = config.loanConfig.oracle.getPrice(address(config.debtToken));
        valueAndPrice.priceDenominator = 10 ** priceDecimals;

        valueAndPrice.debtDenominator = 10 ** debtDecimals;

        valueAndPrice.debtValueWithDecimals = (loan.debtAmt * valueAndPrice.debtPrice) / valueAndPrice.debtDenominator;
    }

    /// @notice Return the loan to value of this loan
    /// @param valueAndPrice Debt and collateral prices, values
    /// @return ltv The loan to value of this loan
    function _calculateLtv(ValueAndPrice memory valueAndPrice) internal pure returns (uint128 ltv) {
        if (valueAndPrice.collateralValue == 0) {
            return type(uint128).max;
        }
        // debtValueWithDecimals(price decimals) collateralValue(base decimals)
        ltv = (
            (valueAndPrice.debtValueWithDecimals * Constants.DECIMAL_BASE_SQ)
                / (valueAndPrice.collateralValue * valueAndPrice.priceDenominator)
        ).toUint128();
    }

    /// @notice Merge collateral data
    function _mergeCollateral(bytes memory collateralDataA, bytes memory collateralDataB)
        internal
        virtual
        returns (bytes memory collateralData);

    /// @notice Transfer collateral from 'from' to 'to'
    function _transferCollateralFrom(address from, address to, bytes memory collateralData) internal virtual;

    /// @notice Transfer collateral from this contracct to 'to'
    function _transferCollateral(address to, bytes memory collateralData) internal virtual;

    /// @notice Return the value of collateral in USD with base decimals
    /// @param collateralData encoded collateral data
    /// @param priceData encoded price data of the collateral
    /// @return collateralValue collateral's value in USD
    function _getCollateralValue(bytes memory collateralData, bytes memory priceData)
        internal
        view
        virtual
        returns (uint256 collateralValue);

    /// @notice Return the encoded price of collateral in USD
    function _getCollateralPriceData(GtConfig memory config) internal view virtual returns (bytes memory priceData);
}
