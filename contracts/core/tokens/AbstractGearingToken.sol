// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../lib/Constants.sol";
import {GearingTokenConstants} from "../lib/GearingTokenConstants.sol";
import {IFlashRepayer} from "./IFlashRepayer.sol";
import {IGearingToken, AggregatorV3Interface, IERC20Metadata, IERC20} from "./IGearingToken.sol";

/**
 * @title TermMax Gearing Token
 * @author Term Structure Labs
 */
abstract contract AbstractGearingToken is
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IGearingToken
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    struct LoanInfo {
        /// @notice Debt amount in underlying token
        uint128 debtAmt;
        /// @notice Encoded collateral data
        bytes collateralData;
    }

    struct ValueAndPrice {
        /// @notice USD value of collateral
        uint256 collateralValue;
        /// @notice USD value of debt with price and token decimals
        uint256 debtValueWithDecimals;
        /// @notice USD price of underlying token
        uint256 underlyingPrice;
        /// @notice Decimals of USD price
        uint256 priceDecimals;
        /// @notice Decimals of underlying token
        uint256 underlyingDecimals;
        /// @notice Encoded USD price of collateral token
        bytes collateralPriceData;
    }

    

    /// @notice Configuturation of Gearing Token
    GtConfig _config;
    /// @notice Total supply of Gearing Token
    uint256 total;
    /// @notice Mapping relationship between Gearing Token id and loan
    mapping(uint256 => LoanInfo) loanMapping;
    /// @notice The switch of GT minting
    bool public canMintGt;

    /**
     * @inheritdoc IGearingToken
     */
    function initialize(
        string memory name,
        string memory symbol,
        GtConfig memory config_,
        bytes memory initalParams
    ) external override initializer {
        __AbstractGearingToken_init(name, symbol, config_);
        __GearingToken_Implement_init(initalParams);
        canMintGt = true;
    }

    function __AbstractGearingToken_init(
        string memory name,
        string memory symbol,
        GtConfig memory config_
    ) internal onlyInitializing {
        __ERC721_init(name, symbol);
        __Ownable_init(config_.market);
        __Pausable_init();
        _config = config_;
        // Market will burn those tokens after maturity
        config_.ft.approve(config_.market, type(uint256).max);
    }

    function __GearingToken_Implement_init(
        bytes memory initalParams
    ) internal virtual;

    /**
     * @inheritdoc IGearingToken
     */
    function setTreasurer(address treasurer) external onlyOwner {
        _config.treasurer = treasurer;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function updateMintingSwitch(bool _canMintGt) external override onlyOwner {
        canMintGt = _canMintGt;
        emit UpdateMintingSwitch(_canMintGt);
    }

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
        return _config.market;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function liquidatable() external view returns (bool) {
        return _config.liquidatable;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function mint(
        address collateralProvider,
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    )
        external
        override
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint256 id)
    {
        if (!canMintGt) {
            revert CanNotMintGtNow();
        }
        _transferCollateralFrom(
            collateralProvider,
            address(this),
            collateralData
        );
        id = _mintInternal(to, debtAmt, collateralData, _config);
    }

    function _mintInternal(
        address to,
        uint128 debtAmt,
        bytes memory collateralData,
        GtConfig memory config
    ) internal returns (uint256 id) {
        LoanInfo memory loan = LoanInfo(debtAmt, collateralData);
        ValueAndPrice memory valueAndPrice = _getValueAndPrice(
            config.underlyingOracle,
            loan,
            config.underlying.decimals()
        );
        _checkDebtValue(valueAndPrice);
        uint128 ltv = _calculateLtv(valueAndPrice);
        if (ltv >= config.maxLtv) {
            revert GtIsNotHealthy(0, to, ltv);
        }
        id = ++total;
        loanMapping[id] = loan;
        _mint(to, id);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function loanInfo(
        uint256 id
    )
        external
        view
        override
        returns (
            address owner,
            uint128 debtAmt,
            uint128 ltv,
            bytes memory collateralData
        )
    {
        owner = ownerOf(id);
        LoanInfo memory loan = loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
        ltv = _calculateLtv(
            _getValueAndPrice(
                _config.underlyingOracle,
                loan,
                _config.underlying.decimals()
            )
        );
    }

    function _burnInternal(uint256 id) internal {
        _burn(id);
        delete loanMapping[id];
    }

    /**
     * @inheritdoc IGearingToken
     */
    function merge(
        uint256[] memory ids
    ) external nonReentrant returns (uint256 newId) {
        uint128 totalDebtAmt;
        bytes memory mergedCollateralData;
        for (uint i = 0; i < ids.length; ++i) {
            uint id = ids[i];
            LoanInfo memory loan = loanMapping[id];
            address owner = ownerOf(id);
            if (msg.sender != owner) {
                revert CanNotMergeLoanWithDiffOwner(id, owner);
            }
            totalDebtAmt += loan.debtAmt;
            mergedCollateralData = i == 0
                ? loan.collateralData
                : _mergeCollateral(mergedCollateralData, loan.collateralData);
            _burnInternal(id);
        }
        newId = _mintInternal(
            msg.sender,
            totalDebtAmt,
            mergedCollateralData,
            _config
        );
        emit MergeGts(msg.sender, newId, ids);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function repay(
        uint256 id,
        uint128 repayAmt,
        bool byUnderlying
    ) external override nonReentrant {
        GtConfig memory config = _config;

        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }

        if (byUnderlying) {
            config.underlying.safeTransferFrom(msg.sender, config.market, repayAmt);
        } else {
            // Those ft tokens have been approved to market and will be burn after maturity
            config.ft.safeTransferFrom(msg.sender, address(this), repayAmt);
        }
        _repay(id, repayAmt);
        emit Repay(id, repayAmt, byUnderlying);
    }

    function flashRepay(
        uint256 id,
        bool byUnderlying,
        bytes calldata callbackData
    ) external override nonReentrant {
        GtConfig memory config = _config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }
        LoanInfo memory loan = loanMapping[id];
        address owner = ownerOf(id);
        // Transfer collateral to the owner
        _transferCollateral(owner, loan.collateralData);
        IERC20 repayToken = byUnderlying? config.underlying:config.ft;

        IFlashRepayer(msg.sender).executeOperation(
            owner,
            repayToken,
            loan.debtAmt,
            config.collateral,
            loan.collateralData,
            callbackData
        );
        repayToken.safeTransferFrom(msg.sender, config.market, loan.debtAmt);
        _burnInternal(id);
        emit Repay(id, loan.debtAmt, byUnderlying);
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
    function removeCollateral(
        uint256 id,
        bytes memory collateralData
    ) external override nonReentrant whenNotPaused {
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

        ValueAndPrice memory valueAndPrice = _getValueAndPrice(
            config.underlyingOracle,
            loan,
            config.underlying.decimals()
        );
        _checkDebtValue(valueAndPrice);
        uint128 ltv = _calculateLtv(valueAndPrice);
        if (ltv >= config.maxLtv) {
            revert GtIsNotHealthy(id, msg.sender, ltv);
        }
        loanMapping[id] = loan;

        emit RemoveCollateral(id, loan.collateralData);
    }

    function _removeCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual returns (bytes memory);

    /**
     * @inheritdoc IGearingToken
     */
    function addCollateral(
        uint256 id,
        bytes memory collateralData
    ) external override nonReentrant {
        if (_config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }
        LoanInfo memory loan = loanMapping[id];

        _transferCollateralFrom(msg.sender, address(this), collateralData);
        loan.collateralData = _addCollateral(loan, collateralData);
        loanMapping[id] = loan;
        emit AddCollateral(id, loan.collateralData);
    }

    function _addCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual returns (bytes memory);

    /**
     * @inheritdoc IGearingToken
     */
    function getLiquidationInfo(
        uint256 id
    ) external view returns (bool isLiquidable, uint128 maxRepayAmt) {
        LoanInfo memory loan = loanMapping[id];
        GtConfig memory config = _config;
        (isLiquidable, maxRepayAmt, , ) = _getLiquidationInfo(loan, config);
    }

    function _getLiquidationInfo(
        LoanInfo memory loan,
        GtConfig memory config
    )
        internal
        view
        returns (
            bool isLiquidable,
            uint128 maxRepayAmt,
            uint128 ltv,
            ValueAndPrice memory valueAndPrice
        )
    {
        valueAndPrice = _getValueAndPrice(
            config.underlyingOracle,
            loan,
            config.underlying.decimals()
        );
        ltv = _calculateLtv(valueAndPrice);

        if (config.liquidatable) {
            // Liquidation cases:
            // t >= m + w => F, "No liquidation after maturity plus liquidation window
            // t >= m && t < m + w => T, "Liquidation allowed during liquidation window"
            // t < m => ltv >= lltv => T, "Liquidation only allowed before maturity if ltv >= lltv"

            if (
                block.timestamp >=
                config.maturity + Constants.LIQUIDATION_WINDOW
            ) {
                isLiquidable = false;
            } else if (block.timestamp >= config.maturity) {
                isLiquidable = true;
                maxRepayAmt = loan.debtAmt;
            } else if (ltv >= config.liquidationLtv) {
                isLiquidable = true;
                // collateralValue(price decimals) and HALF_LIQUIDATION_THRESHOLD(base decimals 1e8)
                maxRepayAmt = (valueAndPrice.collateralValue *
                    Constants.DECIMAL_BASE) /
                    valueAndPrice.priceDecimals <
                    GearingTokenConstants.HALF_LIQUIDATION_THRESHOLD
                    ? loan.debtAmt
                    : loan.debtAmt / 2;
            }
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function liquidate(
        uint256 id,
        uint128 repayAmt
    ) external override nonReentrant whenNotPaused {
        LoanInfo memory loan = loanMapping[id];
        GtConfig memory config = _config;
        if (!config.liquidatable) {
            revert GtDoNotSupportLiquidation();
        }
        (
            bool isLiquidable,
            uint128 maxRepayAmt,
            uint128 ltvBefore,
            ValueAndPrice memory valueAndPrice
        ) = _getLiquidationInfo(loan, config);

        if (!isLiquidable) {
            uint liquidationDeadline = config.maturity +
                Constants.LIQUIDATION_WINDOW;
            if (block.timestamp >= liquidationDeadline) {
                revert CanNotLiquidationAfterFinalDeadline(
                    id,
                    liquidationDeadline
                );
            }
            revert GtIsSafe(id);
        }
        if (repayAmt > maxRepayAmt) {
            revert RepayAmtExceedsMaxRepayAmt(id, repayAmt, maxRepayAmt);
        }
        // Transfer token
        config.underlying.safeTransferFrom(msg.sender, config.market, repayAmt);
        // Do liquidate

        (
            bytes memory cToLiquidator,
            bytes memory cToTreasurer,
            bytes memory remainningC
        ) = _calcLiquidationResult(loan, repayAmt, valueAndPrice);

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
                valueAndPrice.collateralValue = _getCollateralValue(
                    remainningC,
                    valueAndPrice.collateralPriceData
                );
                valueAndPrice.debtValueWithDecimals =
                    (loan.debtAmt * valueAndPrice.underlyingPrice) /
                    valueAndPrice.underlyingDecimals;
                _checkDebtValue(valueAndPrice);
                uint128 ltvAfter = _calculateLtv(valueAndPrice);
                if (ltvBefore < ltvAfter) {
                    revert LtvIncreasedAfterLiquidation(
                        id,
                        ltvBefore,
                        ltvAfter
                    );
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

        emit Liquidate(
            id,
            msg.sender,
            repayAmt,
            cToLiquidator,
            cToTreasurer,
            remainningC
        );
    }

    /// @notice Return the collateral distribution plan after liquidation
    /// @param loan The loan data, contains debt amount and collateral data
    /// @param repayAmt The amount of the debt to be liquidate
    /// @param valueAndPrice Debt and collateral prices, values
    /// @return cToLiquidator Collateral data assigned to liquidator
    /// @return cToTreasurer Collateral data assigned to protocol
    /// @return remainningC Remainning collateral data, will assigned to debt's owner
    ///                     if the debt is fully liquidated.
    function _calcLiquidationResult(
        LoanInfo memory loan,
        uint128 repayAmt,
        ValueAndPrice memory valueAndPrice
    )
        internal
        virtual
        returns (
            bytes memory cToLiquidator,
            bytes memory cToTreasurer,
            bytes memory remainningC
        );

    /**
     * @inheritdoc IGearingToken
     */
    function getCollateralValue(
        bytes memory collateralData
    ) external view override returns (uint256 collateralValue) {
        bytes memory priceData = _getCollateralPriceData();
        return _getCollateralValue(collateralData, priceData);
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
        deliveryData = _delivery(proportion);
        _transferCollateral(to, deliveryData);
    }

    function _delivery(
        uint256 proportion
    ) internal virtual returns (bytes memory deliveryData);

    function _getValueAndPrice(
        AggregatorV3Interface underlyingOracle,
        LoanInfo memory loan,
        uint8 erc20Decimals
    ) internal view returns (ValueAndPrice memory valueAndPrice) {
        valueAndPrice.collateralPriceData = _getCollateralPriceData();
        valueAndPrice.collateralValue = _getCollateralValue(
            loan.collateralData,
            valueAndPrice.collateralPriceData
        );

        (
            valueAndPrice.underlyingPrice,
            valueAndPrice.priceDecimals
        ) = _getPrice(underlyingOracle);

        valueAndPrice.underlyingDecimals = 10 ** erc20Decimals;

        valueAndPrice.debtValueWithDecimals =
            (loan.debtAmt * valueAndPrice.underlyingPrice) /
            valueAndPrice.underlyingDecimals;
    }

    /// @notice Return the loan to value of this loan
    /// @param valueAndPrice Debt and collateral prices, values
    /// @return ltv The loan to value of this loan
    function _calculateLtv(
        ValueAndPrice memory valueAndPrice
    ) internal pure returns (uint128 ltv) {
        if (valueAndPrice.collateralValue == 0) {
            return type(uint128).max;
        }
        // debtValueWithDecimals(price decimals) collateralValue(base decimals)
        ltv = ((valueAndPrice.debtValueWithDecimals *
            Constants.DECIMAL_BASE_SQ) /
            (valueAndPrice.collateralValue * valueAndPrice.priceDecimals))
            .toUint128();
    }

    /// @notice Return the price given by the oracle in USD
    function _getPrice(
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256 price, uint256 decimals) {
        decimals = 10 ** priceFeed.decimals();
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        price = answer.toUint256();
    }

    /// @notice Merge collateral data
    function _mergeCollateral(
        bytes memory collateralDataA,
        bytes memory collateralDataB
    ) internal virtual returns (bytes memory collateralData);

    /// @notice Transfer collateral from 'from' to 'to'
    function _transferCollateralFrom(
        address from,
        address to,
        bytes memory collateralData
    ) internal virtual;

    /// @notice Transfer collateral from this contracct to 'to'
    function _transferCollateral(
        address to,
        bytes memory collateralData
    ) internal virtual;

    /// @notice Return the value of collateral in USD with base decimals
    /// @param collateralData encoded collateral data
    /// @param priceData encoded price data of the collateral
    /// @return collateralValue collateral's value in USD
    function _getCollateralValue(
        bytes memory collateralData,
        bytes memory priceData
    ) internal view virtual returns (uint256 collateralValue);

    /// @notice Return the encoded price of collateral in USD
    function _getCollateralPriceData()
        internal
        view
        virtual
        returns (bytes memory priceData);

    function _checkDebtValue(ValueAndPrice memory valueAndPrice) internal pure {
        uint debtValue = (valueAndPrice.debtValueWithDecimals *
            Constants.DECIMAL_BASE) / valueAndPrice.priceDecimals;
        if (debtValue < GearingTokenConstants.MINIMAL_DEBT_VALUE) {
            revert DebtValueIsTooSmall(debtValue);
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc IGearingToken
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
