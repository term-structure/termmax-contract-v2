// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "../lib/Constants.sol";
import {IFlashRepayer} from "./IFlashRepayer.sol";
import {IGearingToken, AggregatorV3Interface, IERC20Metadata, IERC20} from "./IGearingToken.sol";

/**
 * @title TermMax Gearing Token
 * @author Term Structure Labs
 */
abstract contract AbstractGearingToken is
    OwnableUpgradeable,
    ERC721Upgradeable,
    ReentrancyGuardUpgradeable,
    IGearingToken
{
    using SafeCast for uint256;
    using SafeCast for int256;

    struct LoanInfo {
        /// @notice Debt amount in underlying token
        uint128 debtAmt;
        /// @notice Encoded collateral data
        bytes collateralData;
    }

    struct GearingTokenStorage {
        /// @notice Configuturation of Gearing Token
        GtConfig config;
        /// @notice Total supply of Gearing Token
        uint256 total;
        /// @notice Mapping relationship between Gearing Token id and loan
        mapping(uint256 => LoanInfo) loanMapping;
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

    /// @notice The percentage of repay amount to liquidator while do liquidate, decimals 1e8
    uint256 constant REWARD_TO_LIQUIDATOR = 0.05e8;
    /// @notice The percentage of repay amount to protocol while do liquidate, decimals 1e8
    uint256 constant REWARD_TO_PROTOCOL = 0.05e8;
    /// @notice Semi-liquidation threshold: if the value of the collateral reaches this value,
    ///         only partial liquidation can be performed, decimals 1e8.
    uint256 constant HALF_LIQUIDATION_THRESHOLD = 10000e8;
    /// @notice Minimum debt value, decimals 1e8.
    uint256 constant MINIMAL_DEBT_VALUE = 5e8;

    uint256 constant UINT_MAX = type(uint256).max;
    uint128 constant UINT128_MAX = type(uint128).max;

    bytes32 internal constant STORAGE_SLOT_GEARING_NFT =
        bytes32(uint256(keccak256("TermMax.storage.GearingToken")) - 1);

    function _getGearingTokenStorage()
        internal
        pure
        returns (GearingTokenStorage storage s)
    {
        bytes32 slot = STORAGE_SLOT_GEARING_NFT;
        assembly {
            s.slot := slot
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function initialize(
        string memory name,
        string memory symbol,
        GtConfig memory config,
        bytes memory initalParams
    ) external override initializer {
        __AbstractGearingToken_init(name, symbol, config);
        __GearingToken_Implement_init(initalParams);
    }

    function __AbstractGearingToken_init(
        string memory name,
        string memory symbol,
        GtConfig memory config
    ) internal onlyInitializing {
        __ERC721_init(name, symbol);
        __Ownable_init(config.market);
        GearingTokenStorage storage s = _getGearingTokenStorage();
        s.config = config;
        // Market will burn those tokens after maturity
        config.ft.approve(config.market, UINT_MAX);
    }

    function __GearingToken_Implement_init(
        bytes memory initalParams
    ) internal virtual;

    /**
     * @inheritdoc IGearingToken
     */
    function setTreasurer(address treasurer) external onlyOwner {
        _getGearingTokenStorage().config.treasurer = treasurer;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function getGtConfig() external view override returns (GtConfig memory) {
        return _getGearingTokenStorage().config;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function marketAddr() public view override returns (address) {
        return _getGearingTokenStorage().config.market;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function liquidatable() external view returns (bool) {
        return _getGearingTokenStorage().config.liquidatable;
    }

    /**
     * @inheritdoc IGearingToken
     */
    function mint(
        address collateralProvider,
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external override onlyOwner returns (uint256 id) {
        GearingTokenStorage storage s = _getGearingTokenStorage();
        _transferCollateralFrom(
            collateralProvider,
            address(this),
            collateralData
        );
        id = _mintInternal(to, debtAmt, collateralData, s);
    }

    function _mintInternal(
        address to,
        uint128 debtAmt,
        bytes memory collateralData,
        GearingTokenStorage storage s
    ) internal returns (uint256 id) {
        LoanInfo memory loan = LoanInfo(debtAmt, collateralData);
        ValueAndPrice memory valueAndPrice = _getValueAndPrice(
            s.config.underlyingOracle,
            loan,
            s.config.underlying.decimals()
        );
        _checkDebtValue(valueAndPrice);
        uint128 ltv = _calculateLtv(valueAndPrice);
        if (ltv >= s.config.maxLtv) {
            revert GtIsNotHealthy(0, to, ltv);
        }
        id = ++s.total;
        s.loanMapping[id] = loan;
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
        GearingTokenStorage storage s = _getGearingTokenStorage();
        LoanInfo memory loan = s.loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
        ltv = _calculateLtv(
            _getValueAndPrice(
                s.config.underlyingOracle,
                loan,
                s.config.underlying.decimals()
            )
        );
    }

    function _burnInternal(uint256 id, GearingTokenStorage storage s) internal {
        _burn(id);
        delete s.loanMapping[id];
    }

    /**
     * @inheritdoc IGearingToken
     */
    function merge(uint256[] memory ids) external returns (uint256 newId) {
        GearingTokenStorage storage s = _getGearingTokenStorage();
        uint128 totalDebtAmt;
        bytes memory mergedCollateralData;
        for (uint i = 0; i < ids.length; ++i) {
            uint id = ids[i];
            LoanInfo memory loan = s.loanMapping[id];
            address owner = ownerOf(id);
            if (msg.sender != owner) {
                revert CanNotMergeLoanWithDiffOwner(id, owner);
            }
            totalDebtAmt += loan.debtAmt;
            mergedCollateralData = i == 0
                ? loan.collateralData
                : _mergeCollateral(mergedCollateralData, loan.collateralData);
            _burnInternal(id, s);
        }
        newId = _mintInternal(
            msg.sender,
            totalDebtAmt,
            mergedCollateralData,
            s
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
        GearingTokenStorage storage s = _getGearingTokenStorage();
        GtConfig memory config = s.config;

        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }

        if (byUnderlying) {
            config.underlying.transferFrom(msg.sender, config.market, repayAmt);
        } else {
            // Those ft tokens have been approved to market and will be burn after maturity
            config.ft.transferFrom(msg.sender, address(this), repayAmt);
        }
        _repay(s, id, repayAmt);
        emit Repay(id, repayAmt, byUnderlying);
    }

    function flashRepay(
        uint256 id,
        bytes calldata callbackData
    ) external override {
        GearingTokenStorage storage s = _getGearingTokenStorage();
        GtConfig memory config = s.config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }
        LoanInfo memory loan = s.loanMapping[id];
        address owner = ownerOf(id);
        // Transfer collateral to the owner
        _transferCollateral(owner, loan.collateralData);
        IFlashRepayer(msg.sender).executeOperation(
            owner,
            config.underlying,
            loan.debtAmt,
            config.collateral,
            loan.collateralData,
            callbackData
        );
        config.underlying.transferFrom(msg.sender, config.market, loan.debtAmt);
        _burnInternal(id, s);
        emit Repay(id, loan.debtAmt, true);
    }

    function _repay(
        GearingTokenStorage storage s,
        uint256 id,
        uint128 repayAmt
    ) internal {
        LoanInfo memory loan = s.loanMapping[id];
        if (repayAmt > loan.debtAmt) {
            revert RepayAmtExceedsMaxRepayAmt(id, repayAmt, loan.debtAmt);
        }
        if (repayAmt == loan.debtAmt) {
            address gtOwner = ownerOf(id);
            // Burn this nft
            _burnInternal(id, s);
            _transferCollateral(gtOwner, loan.collateralData);
        } else {
            uint128 debtAmt = loan.debtAmt - repayAmt;
            s.loanMapping[id].debtAmt = debtAmt;
        }
    }

    /**
     * @inheritdoc IGearingToken
     */
    function removeCollateral(
        uint256 id,
        bytes memory collateralData
    ) external override nonReentrant {
        if (msg.sender != ownerOf(id)) {
            revert CallerIsNotTheOwner(id);
        }

        GearingTokenStorage storage s = _getGearingTokenStorage();
        GtConfig memory config = s.config;
        if (config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }

        LoanInfo memory loan = s.loanMapping[id];
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
        s.loanMapping[id] = loan;

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
        GearingTokenStorage storage s = _getGearingTokenStorage();
        if (s.config.maturity <= block.timestamp) {
            revert GtIsExpired(id);
        }
        LoanInfo memory loan = s.loanMapping[id];

        _transferCollateralFrom(msg.sender, address(this), collateralData);
        loan.collateralData = _addCollateral(loan, collateralData);
        s.loanMapping[id] = loan;
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
        GearingTokenStorage storage s = _getGearingTokenStorage();
        LoanInfo memory loan = s.loanMapping[id];
        GtConfig memory config = s.config;
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
                    HALF_LIQUIDATION_THRESHOLD
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
    ) external override nonReentrant {
        GearingTokenStorage storage s = _getGearingTokenStorage();
        LoanInfo memory loan = s.loanMapping[id];
        GtConfig memory config = s.config;
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
        config.underlying.transferFrom(msg.sender, config.market, repayAmt);
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
            _burnInternal(id, s);
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
            s.loanMapping[id] = loan;
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
            return UINT128_MAX;
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
        if (debtValue < MINIMAL_DEBT_VALUE) {
            revert DebtValueIsTooSmall(debtValue);
        }
    }
}
