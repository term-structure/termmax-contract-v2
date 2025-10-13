// SPDX-License-Identifier:  BUSL-1.1
pragma solidity ^0.8.27;

import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {GearingTokenConstants} from "../../v1/lib/GearingTokenConstants.sol";
import {TransferUtils} from "../../v1/lib/TransferUtils.sol";
import {IFlashRepayer} from "../../v1/tokens/IFlashRepayer.sol";
import {IGearingToken, IERC20Metadata, IERC20} from "../../v1/tokens/IGearingToken.sol";
import {GearingTokenErrors} from "../../v1/errors/GearingTokenErrors.sol";
import {GearingTokenEvents} from "../../v1/events/GearingTokenEvents.sol";
import {GtConfig, IOracle} from "../../v1/storage/TermMaxStorage.sol";
import {IGearingTokenV2} from "./IGearingTokenV2.sol";
import {GearingTokenEventsV2} from "../events/GearingTokenEventsV2.sol";
import {GearingTokenErrorsV2} from "../errors/GearingTokenErrorsV2.sol";
import {VersionV2} from "../VersionV2.sol";
import {DelegateAble} from "../lib/DelegateAble.sol";

/**
 * @title TermMax Gearing Token
 * @author Term Structure Labs
 */
abstract contract AbstractGearingTokenV2 is
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuardUpgradeable,
    IGearingToken,
    IGearingTokenV2,
    GearingTokenErrors,
    GearingTokenEvents,
    VersionV2,
    DelegateAble
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IERC20Metadata;
    using Math for *;

    struct LoanInfo {
        /// @notice Debt amount in debtToken token
        uint128 debtAmt;
        /// @notice Encoded collateral data
        bytes collateralData;
    }

    struct ValueAndPrice {
        /// @notice USD value of collateral
        uint256 collateralValue;
        /// @notice USD value of debt contains price and token decimals
        uint256 debtValueWithDecimals;
        /// @notice USD price of debt token
        uint256 debtPrice;
        /// @notice Denominator of USD price, e.g. 10**priceDecimals
        uint256 priceDenominator;
        /// @notice Denominator of debt token, e.g. 10**debtToken.decimals()
        uint256 debtDenominator;
        /// @notice Encoded USD price of collateral token, e.g. priceData is
        ///         abi.encode(price, priceDenominator, collateralDenominator)
        ///         where gt is GearingTokenWithERC20
        bytes collateralPriceData;
    }

    /// @notice Configuration of Gearing Token
    GtConfig internal _config;
    /// @notice Total supply of Gearing Token
    uint256 internal totalIds;
    /// @notice Denominator of debt token
    uint256 internal debtDenominator;
    /// @notice Mapping relationship between Gearing Token id and loan
    mapping(uint256 => LoanInfo) internal loanMapping;

    modifier isOwnerOrDelegate(uint256 id, address msgSender) {
        _checkIsOwnerOrDelegate(id, msgSender);
        _;
    }

    function _checkIsOwnerOrDelegate(uint256 id, address msgSender) internal view {
        address owner = ownerOf(id);
        if (msgSender != owner && !isDelegate(owner, msgSender)) {
            revert GearingTokenErrors.AuthorizationFailed(id, msgSender);
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function initialize(string memory name, string memory symbol, GtConfig memory config_, bytes memory initalParams)
        external
        virtual
        override
        initializer
    {
        __AbstractGearingToken_init(name, symbol, config_);
        __GearingToken_Implement_init(initalParams);
        emit GearingTokenEventsV2.GearingTokenInitialized(msg.sender, name, symbol, initalParams);
    }

    function __AbstractGearingToken_init(string memory name, string memory symbol, GtConfig memory config_)
        internal
        onlyInitializing
    {
        if (config_.loanConfig.liquidationLtv <= config_.loanConfig.maxLtv) {
            revert LiquidationLtvMustBeGreaterThanMaxLtv();
        }
        if (config_.loanConfig.liquidationLtv > Constants.DECIMAL_BASE) {
            revert GearingTokenErrorsV2.InvalidLiquidationLtv();
        }
        __ERC721_init_unchained(name, symbol);
        __EIP712_init_unchained(name, getVersion());
        __Ownable_init_unchained(msg.sender);
        _config = config_;
        debtDenominator = 10 ** _config.debtToken.decimals();
    }

    function __GearingToken_Implement_init(bytes memory initalParams) internal virtual;

    /**
     * @inheritdoc IGearingToken
     */
    function setTreasurer(address treasurer) external virtual onlyOwner {
        _config.treasurer = treasurer;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function updateConfig(bytes memory configData) external virtual onlyOwner {
        _updateConfig(configData);
        emit UpdateConfig(configData);
    }

    function _updateConfig(bytes memory configData) internal virtual;

    /**
     * @inheritdoc IGearingToken
     */
    function getGtConfig() external view virtual override returns (GtConfig memory) {
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
    function liquidatable() external view virtual returns (bool) {
        return _config.loanConfig.liquidatable;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function mint(address collateralProvider, address to, uint128 debtAmt, bytes memory collateralData)
        external
        virtual
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
        id = ++totalIds;
        loanMapping[id] = loan;
        _safeMint(to, id);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function augmentDebt(address caller, uint256 id, uint256 ftAmt)
        external
        virtual
        override
        nonReentrant
        onlyOwner
        isOwnerOrDelegate(id, caller)
    {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
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
        virtual
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
    function merge(uint256[] memory ids) external virtual nonReentrant returns (uint256 newId) {
        if (ids.length == 0) {
            revert GearingTokenErrorsV2.GtIdArrayIsEmpty();
        }
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
        }
        newId = ids[0];
        LoanInfo memory firstLoan = loanMapping[newId];

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            _checkIsOwnerOrDelegate(id, msg.sender);
            if (i != 0) {
                if (id == newId) {
                    revert GearingTokenErrorsV2.DuplicateIdInMerge(id);
                }
                LoanInfo memory loan = loanMapping[id];
                firstLoan.debtAmt += loan.debtAmt;
                firstLoan.collateralData = _mergeCollateral(firstLoan.collateralData, loan.collateralData);
                _burnInternal(id);
            }
        }
        loanMapping[newId] = firstLoan;
        emit MergeGts(msg.sender, newId, ids);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function repay(uint256 id, uint128 repayAmt, bool byDebtToken) external virtual override nonReentrant {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
        }
        (LoanInfo memory loan, bool repayAll, uint128 finalRepayAmt) = _repay(id, repayAmt);
        if (repayAll) {
            _transferCollateral(ownerOf(id), loan.collateralData);
            _burnInternal(id);
        } else {
            loanMapping[id] = loan;
        }
        if (byDebtToken) {
            config.debtToken.safeTransferFrom(msg.sender, marketAddr(), finalRepayAmt);
        } else {
            // Those ft tokens have been approved to market and will be burn after maturity
            config.ft.safeTransferFrom(msg.sender, marketAddr(), finalRepayAmt);
        }
        emit GearingTokenEventsV2.Repay(id, finalRepayAmt, byDebtToken, repayAll);
    }

    /// @inheritdoc IGearingToken
    /// @notice This function is deprecated, please use `flashRepay(
    //     uint256 id,
    //     uint128 repayAmt,
    //     bool byDebtToken,
    //     bytes memory removedCollateral,
    //     bytes calldata callbackData
    // )` instead
    function flashRepay(uint256 id, bool byDebtToken, bytes calldata callbackData)
        external
        virtual
        override
        nonReentrant
        isOwnerOrDelegate(id, msg.sender)
    {
        LoanInfo memory loan = loanMapping[id];
        _flashRepay(id, loan.debtAmt, byDebtToken, loan.collateralData, callbackData);
    }

    function flashRepay(
        uint256 id,
        uint128 repayAmt,
        bool byDebtToken,
        bytes memory removedCollateral,
        bytes calldata callbackData
    ) external virtual override nonReentrant isOwnerOrDelegate(id, msg.sender) returns (bool) {
        return _flashRepay(id, repayAmt, byDebtToken, removedCollateral, callbackData);
    }

    function _flashRepay(
        uint256 id,
        uint128 repayAmt,
        bool byDebtToken,
        bytes memory removedCollateral,
        bytes calldata callbackData
    ) internal returns (bool) {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
        }
        // All collteral will be removed in _repay function if repayAll is true
        (LoanInfo memory loan, bool repayAll, uint128 finalRepayAmt) = _repay(id, repayAmt);
        if (repayAll) {
            _burnInternal(id);
            removedCollateral = loan.collateralData;
        } else {
            loan.collateralData = _removeCollateral(loan, removedCollateral);
            ValueAndPrice memory valueAndPrice = _getValueAndPrice(config, loan);
            uint128 ltv = _calculateLtv(valueAndPrice);
            require(ltv <= config.loanConfig.maxLtv, GtIsNotHealthy(id, ownerOf(id), ltv));
            loanMapping[id] = loan;
        }
        // Transfer collateral to the caller
        _transferCollateral(msg.sender, removedCollateral);

        IERC20 repayToken = byDebtToken ? config.debtToken : config.ft;

        IFlashRepayer(msg.sender).executeOperation(
            repayToken, finalRepayAmt, config.collateral, removedCollateral, callbackData
        );
        repayToken.safeTransferFrom(msg.sender, marketAddr(), finalRepayAmt);
        emit GearingTokenEventsV2.FlashRepay(id, msg.sender, finalRepayAmt, byDebtToken, repayAll, removedCollateral);
        return repayAll;
    }

    function _repay(uint256 id, uint128 repayAmt)
        internal
        view
        returns (LoanInfo memory loan, bool repayAll, uint128 finalRepayAmt)
    {
        loan = loanMapping[id];
        if (repayAmt > loan.debtAmt) {
            repayAmt = loan.debtAmt;
        }
        loan.debtAmt = loan.debtAmt - repayAmt;
        finalRepayAmt = repayAmt;
        if (loan.debtAmt == 0) {
            repayAll = true;
        }
    }

    /// @notice Repay the debt of Gearing Token and remove collateral
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt you want to repay
    /// @param byDebtToken Repay using debtToken token or bonds token
    /// @param removedCollateral The collateral data to be removed
    /// @return repayAll Whether the repayment is complete
    /// @return finalRepayAmt The final amount repaid
    function repayAndRemoveCollateral(
        uint256 id,
        uint128 repayAmt,
        bool byDebtToken,
        address collateralRecipient,
        bytes memory removedCollateral
    ) external virtual nonReentrant isOwnerOrDelegate(id, msg.sender) returns (bool repayAll, uint128 finalRepayAmt) {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
        }
        LoanInfo memory loan;
        (loan, repayAll, finalRepayAmt) = _repay(id, repayAmt);
        loan.collateralData = _removeCollateral(loan, removedCollateral);
        if (!repayAll) {
            ValueAndPrice memory valueAndPrice = _getValueAndPrice(config, loan);
            uint128 ltv = _calculateLtv(valueAndPrice);
            require(ltv <= config.loanConfig.maxLtv, GtIsNotHealthy(id, ownerOf(id), ltv));
        }
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
     * @inheritdoc IGearingToken
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
        loan.collateralData = _removeCollateral(loan, collateralData);
        if (loan.debtAmt != 0) {
            ValueAndPrice memory valueAndPrice = _getValueAndPrice(config, loan);
            uint128 ltv = _calculateLtv(valueAndPrice);
            if (ltv > config.loanConfig.maxLtv) {
                revert GtIsNotHealthy(id, msg.sender, ltv);
            }
        }
        loanMapping[id] = loan;

        // Transfer collateral to the owner
        _transferCollateral(msg.sender, collateralData);

        emit RemoveCollateral(id, loan.collateralData);
    }

    function _removeCollateral(LoanInfo memory loan, bytes memory collateralData)
        internal
        virtual
        returns (bytes memory);

    /**
     * @inheritdoc IGearingToken
     */
    function addCollateral(uint256 id, bytes memory collateralData) external virtual override nonReentrant {
        if (_config.maturity <= block.timestamp) {
            revert GearingTokenErrorsV2.GtIsExpired();
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
        virtual
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
                maxRepayAmt = valueAndPrice.collateralValue.mulDiv(
                    Constants.DECIMAL_BASE, valueAndPrice.priceDenominator
                ) < GearingTokenConstants.HALF_LIQUIDATION_THRESHOLD ? loan.debtAmt : loan.debtAmt / 2;
            }
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function liquidate(uint256 id, uint128 repayAmt, bool byDebtToken) external virtual override nonReentrant {
        LoanInfo memory loan = loanMapping[id];
        GtConfig memory config = _config;
        if (!config.loanConfig.liquidatable) {
            revert GtDoNotSupportLiquidation();
        }
        (bool isLiquidable, uint128 maxRepayAmt,, ValueAndPrice memory valueAndPrice) =
            _getLiquidationInfo(loan, config);

        if (!isLiquidable) {
            uint256 liquidationDeadline = config.maturity + Constants.LIQUIDATION_WINDOW;
            if (block.timestamp >= liquidationDeadline) {
                revert CanNotLiquidationAfterFinalDeadline(id, liquidationDeadline);
            }
            revert GtIsSafe(id);
        }
        if (repayAmt > maxRepayAmt) {
            repayAmt = maxRepayAmt;
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
    function getCollateralValue(bytes memory collateralData)
        external
        view
        virtual
        override
        returns (uint256 collateralValue)
    {
        bytes memory priceData = _getCollateralPriceData(_config);
        return _getCollateralValue(collateralData, priceData);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function previewDelivery(uint256 proportion) external view virtual override returns (bytes memory deliveryData) {
        deliveryData = _delivery(proportion);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function delivery(uint256 proportion, address to)
        external
        virtual
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
        // Price decimals may change, so we need to calculate the price denominator
        valueAndPrice.priceDenominator = 10 ** priceDecimals;

        valueAndPrice.debtDenominator = debtDenominator;

        valueAndPrice.debtValueWithDecimals =
            loan.debtAmt.mulDiv(valueAndPrice.debtPrice, valueAndPrice.debtDenominator);
    }

    /// @notice Return the loan to value of this loan
    /// @param valueAndPrice Debt and collateral prices, values
    /// @return ltv The loan to value of this loan
    function _calculateLtv(ValueAndPrice memory valueAndPrice) internal pure returns (uint128 ltv) {
        if (valueAndPrice.collateralValue == 0) {
            return type(uint128).max;
        }
        // debtValueWithDecimals(price decimals) collateralValue(base decimals)
        ltv = valueAndPrice.debtValueWithDecimals.mulDiv(
            Constants.DECIMAL_BASE_SQ, valueAndPrice.collateralValue * valueAndPrice.priceDenominator
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

    /**
     * @notice Get the domain separator for the token
     * @return The domain separator of the token at current chain
     */
    function DOMAIN_SEPARATOR() public view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }
}
