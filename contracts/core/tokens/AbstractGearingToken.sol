// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "../lib/Constants.sol";
import {IGearingToken, AggregatorV3Interface, IERC20} from "./IGearingToken.sol";

/**
 * @title Term Max Gearing Token
 * @author Term Structure Labs
 */
abstract contract AbstractGearingToken is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    ReentrancyGuardUpgradeable,
    IGearingToken
{
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice Error for msg.sender is not the market
    error CallerIsNotTheMarket();
    /// @notice Error for merge loans have different owner
    error CanNotMergeLoanWithDiffOwner();
    /// @notice Error for liquidate loan when Gearing Token don't support liquidation
    error GtDoNotSupportLiquidation();
    /// @notice Error for repay the loan after maturity day
    /// @param id The id of Gearing Token
    error GtIsExpired(uint256 id);
    /// @notice Error for liquidate loan when its ltv less than liquidation threshhold
    /// @param id The id of Gearing Token
    error GtIsSafe(uint256 id);
    /// @notice Error for the ltv of loan is bigger than maxium ltv
    /// @param owner The owner of this loan
    /// @param ltv The loan to value
    error GtIsNotHealthy(address owner, uint128 ltv);
    /// @notice Error for the ltv increase after liquidation
    /// @param ltvBefore Loan to value before liquidation
    /// @param ltvAfter Loan to value after liquidation
    error LtvIncreasedAfterLiquidation(uint256 ltvBefore, uint256 ltvAfter);
    /// @notice Error for unauthorized operation
    /// @param id The id of Gearing Token
    error CallerIsNotTheOwner(uint256 id);
    /// @notice Error for liquidate the loan with invalid repay amount
    error RepayAmtExceedsMaxRepayAmt(uint128 repayAmt, uint128 maxRepayAmt);

    /// @notice Emitted when merging multiple Gearing Tokens into one
    /// @param sender The owner of those tokens
    /// @param newId The id of new Gearing Token
    /// @param ids The array of Gearing Tokens id were merged
    event MergeGts(
        address indexed sender,
        uint256 indexed newId,
        uint256[] ids
    );
    /// @notice Emitted when removing collateral from the loan
    /// @param id The id of Gearing Token
    /// @param newCollateralData Collateral data after removal
    event RemoveCollateral(uint256 indexed id, bytes newCollateralData);

    /// @notice Emitted when adding collateral to the loan
    /// @param id The id of Gearing Token
    /// @param newCollateralData Collateral data after additional
    event AddCollateral(uint256 indexed id, bytes newCollateralData);

    /// @notice Emitted when repaying the debt of Gearing Token
    /// @param id The id of Gearing Token
    /// @param repayAmt The amount of debt repaid
    /// @param byUnderlying Repay using underlying token or bonds token
    event Repay(uint256 indexed id, uint256 repayAmt, bool byUnderlying);

    /// @notice Emitted when liquidating Gearing Token
    /// @param id The id of Gearing Token
    /// @param liquidator The liquidator
    /// @param repayAmt The amount of debt liquidated
    /// @param cToLiquidator Collateral data assigned to liquidator
    /// @param cToTreasurer Collateral data assigned to protocol
    /// @param remainningC Remainning collateral data
    event Liquidate(
        uint256 indexed id,
        address indexed liquidator,
        uint128 repayAmt,
        bytes cToLiquidator,
        bytes cToTreasurer,
        bytes remainningC
    );

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
        /// @notice USD value of debt
        uint256 debtValue;
        /// @notice USD price of underlying token
        uint256 underlyingPrice;
        /// @notice Decimals of USD price
        uint256 priceDecimals;
        /// @notice Encoded USD price of collateral token
        bytes collateralPriceData;
    }

    /// @notice The percentage of repay amount to liquidator while do liquidate
    uint256 constant REWARD_TO_LIQUIDATOR = 5e6;
    /// @notice The percentage of repay amount to protocol while do liquidate
    uint256 constant REWARD_TO_PROTOCOL = 5e6;
    /// @notice Semi-liquidation threshold: if the value of the collateral reaches this value,
    ///         only partial liquidation can be performed.
    uint256 constant HALF_LIQUIDATION_THRESHOLD = 10000e8;
    uint256 constant UINT_MAX = 2 ** 256 - 1;

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

    function __AbstractGearingToken_init(
        string memory name,
        string memory symbol,
        address admin,
        GtConfig memory config
    ) internal onlyInitializing {
        __ERC721_init(name, symbol);
        __Ownable_init(admin);
        GearingTokenStorage storage s = _getGearingTokenStorage();
        s.config = config;
        // Market will burn those tokens after maturity
        config.ft.approve(config.market, UINT_MAX);
    }

    /**
     * @inheritdoc IGearingToken
     */
    function setTreasurer(address treasurer) external {
        if (msg.sender != marketAddr()) {
            revert CallerIsNotTheMarket();
        }
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
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external override returns (uint256 id) {
        GearingTokenStorage storage s = _getGearingTokenStorage();
        if (msg.sender != s.config.market) {
            revert CallerIsNotTheMarket();
        }
        _transferCollateralFrom(to, address(this), collateralData);
        id = _mintInternal(to, debtAmt, collateralData, s);
    }

    function _mintInternal(
        address to,
        uint128 debtAmt,
        bytes memory collateralData,
        GearingTokenStorage storage s
    ) internal returns (uint256 id) {
        LoanInfo memory loan = LoanInfo(debtAmt, collateralData);
        (uint128 ltv, ) = _calculateLtv(s.config.underlyingOracle, loan);
        if (ltv >= s.config.maxLtv) {
            revert GtIsNotHealthy(to, ltv);
        }
        id = s.total++;
        s.loanMapping[id] = LoanInfo(debtAmt, collateralData);
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
        (ltv, ) = _calculateLtv(s.config.underlyingOracle, loan);
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
            if (msg.sender != ownerOf(id)) {
                revert CanNotMergeLoanWithDiffOwner();
            }
            totalDebtAmt += loan.debtAmt;
            mergedCollateralData = _mergeCollateral(
                mergedCollateralData,
                loan.collateralData
            );
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

        if (config.maturity >= block.timestamp) {
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

    function _repay(
        GearingTokenStorage storage s,
        uint256 id,
        uint128 repayAmt
    ) internal {
        address gtOwner = ownerOf(id);
        LoanInfo memory loan = s.loanMapping[id];
        if (repayAmt == loan.debtAmt) {
            // Burn this nft
            _burnInternal(id, s);
            _transferCollateral(gtOwner, loan.collateralData);
        } else {
            s.loanMapping[id].debtAmt -= repayAmt;
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
        LoanInfo memory loan = s.loanMapping[id];
        loan.collateralData = _removeCollateral(loan, collateralData);

        _transferCollateral(msg.sender, collateralData);

        (uint128 ltv, ) = _calculateLtv(s.config.underlyingOracle, loan);
        if (ltv >= s.config.maxLtv) {
            revert GtIsNotHealthy(msg.sender, ltv);
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
        LoanInfo memory loan = s.loanMapping[id];

        _transferCollateralFrom(msg.sender, address(this), collateralData);
        loan.collateralData = _addCollateral(loan, collateralData);

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
        (isLiquidable, maxRepayAmt, ) = _getLiquidationInfo(loan, config);
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
            ValueAndPrice memory valueAndPrice
        )
    {
        uint128 ltv;
        (ltv, valueAndPrice) = _calculateLtv(config.underlyingOracle, loan);
        bool isExpired = block.timestamp >= config.maturity &&
            block.timestamp < config.maturity + Constants.LIQUIDATION_WINDOW;
        isLiquidable = isExpired || ltv >= config.liquidationLtv;

        maxRepayAmt = _calculateMaxRepayAmt(
            loan,
            isExpired,
            valueAndPrice.collateralValue,
            HALF_LIQUIDATION_THRESHOLD
        );
    }

    /// @notice Returns the maximum amount of debt liquidation
    /// @param loan The loan data, contains debt amount and collateral data
    /// @param isExpired Indicates whether the debt is expired
    /// @param collateralValue USD value of collateral
    /// @param halfLiquidationThreshold Semi-liquidated threshold in USD
    function _calculateMaxRepayAmt(
        LoanInfo memory loan,
        bool isExpired,
        uint256 collateralValue,
        uint256 halfLiquidationThreshold
    ) internal pure returns (uint128 maxRepayAmt) {
        maxRepayAmt = collateralValue < halfLiquidationThreshold || isExpired
            ? loan.debtAmt
            : loan.debtAmt / 2;
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
            ValueAndPrice memory valueAndPrice
        ) = _getLiquidationInfo(loan, config);

        if (!isLiquidable) {
            revert GtIsSafe(id);
        }
        if (repayAmt > maxRepayAmt) {
            revert RepayAmtExceedsMaxRepayAmt(repayAmt, maxRepayAmt);
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
                uint ltvBefore = (valueAndPrice.debtValue *
                    Constants.DECIMAL_BASE) / valueAndPrice.collateralValue;

                uint remainningCollateralValue = _getCollateralValue(
                    remainningC,
                    valueAndPrice.collateralPriceData
                );
                uint remainningDebtValue = (loan.debtAmt *
                    valueAndPrice.underlyingPrice) /
                    valueAndPrice.priceDecimals;
                uint ltvAfter = (remainningDebtValue * Constants.DECIMAL_BASE) /
                    remainningCollateralValue;
                if (ltvBefore < ltvAfter) {
                    revert LtvIncreasedAfterLiquidation(ltvBefore, ltvAfter);
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

    /// @notice Return the loan to value of this loan
    /// @param underlyingOracle The oracle of underlying token
    /// @param loan The loan data, contains debt amount and collateral data
    /// @return ltv The loan to value of this loan
    /// @return valueAndPrice Debt and collateral prices, values
    function _calculateLtv(
        AggregatorV3Interface underlyingOracle,
        LoanInfo memory loan
    ) internal view returns (uint128 ltv, ValueAndPrice memory valueAndPrice) {
        valueAndPrice.collateralPriceData = _getCollateralPriceData();
        valueAndPrice.collateralValue = _getCollateralValue(
            loan.collateralData,
            valueAndPrice.collateralPriceData
        );
        (
            valueAndPrice.underlyingPrice,
            valueAndPrice.priceDecimals
        ) = _getPrice(underlyingOracle);
        valueAndPrice.debtValue =
            (loan.debtAmt * valueAndPrice.underlyingPrice) /
            valueAndPrice.priceDecimals;
        ltv = ((valueAndPrice.debtValue * Constants.DECIMAL_BASE) /
            valueAndPrice.collateralValue).toUint128();
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

    /// @notice Return the value of collateral in USD
    /// @param collateralData encoded collateral data
    /// @param priceData encoded price data of the collateral
    /// @return collateralValue collateral's value in USD
    function _getCollateralValue(
        bytes memory collateralData,
        bytes memory priceData
    ) internal pure virtual returns (uint256 collateralValue);

    /// @notice Return the encoded price of collateral in USD
    function _getCollateralPriceData()
        internal
        view
        virtual
        returns (bytes memory priceData);
}
