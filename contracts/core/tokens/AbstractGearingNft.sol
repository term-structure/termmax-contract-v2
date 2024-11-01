// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "../lib/Constants.sol";
import {IGearingNft, AggregatorV3Interface, IERC20} from "./IGearingNft.sol";

abstract contract AbstractGearingNft is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    ReentrancyGuardUpgradeable,
    IGearingNft
{
    using SafeCast for uint256;
    using SafeCast for int256;

    error OnlyMarketCanMintGt();
    error CanNotMergeLoanWithDiffOwner();
    error GtDoNotSupportLiquidation();
    error GNftIsSafe(address liquidator, uint256 id);
    error GNftIsNotHealthy(
        address owner,
        uint128 debtAmt,
        uint128 ltv,
        bytes collateralData
    );
    error LtvIncreasedAfterLiquidation(
        address liquidator,
        uint128 debtAmt,
        uint128 repayAmt,
        bytes collateralData
    );
    error SenderIsNotTheOwner(address sender, uint256 id);
    error NumeratorMustLessThanBasicDecimals();
    /// @notice Error for liquidate the loan with invalid repay amount
    error RepayAmtExceedsMaxRepayAmt(uint128 repayAmt, uint128 maxRepayAmt);

    event MergeGNfts(
        address indexed sender,
        uint256 indexed newId,
        uint256[] ids
    );

    event RemoveCollateral(uint256 indexed id, bytes newCollateralData);

    event AddCollateral(uint256 indexed id, bytes newCollateralData);

    event Repay(uint256 indexed id, uint256 repayAmt, bool byUnderlying);

    event LiquidateGt(
        uint256 indexed id,
        address indexed liquidator,
        uint128 repayAmt,
        bytes cToLiquidator,
        bytes cToTreasurer,
        bytes remainningCollateralData
    );

    struct LoanInfo {
        uint128 debtAmt;
        bytes collateralData;
    }

    struct GearingNftStorage {
        GtConfig config;
        uint256 total;
        mapping(uint256 => LoanInfo) loanMapping;
    }

    struct ValueAndPrice {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 underlyingPrice;
        uint256 priceDecimals;
        bytes collateralPriceData;
    }

    // The percentage of repay amount to liquidator while do liquidate
    uint256 constant REWARD_TO_LIQUIDATOR = 5e6;
    // The percentage of repay amount to protocol while do liquidate
    uint256 constant REWARD_TO_PROTOCOL = 5e6;
    uint256 constant HALF_LIQUIDATION_THRESHOLD = 10000e8;
    uint256 constant UINT_MAX = 2 ** 256 - 1;

    bytes32 internal constant STORAGE_SLOT_GEARING_NFT =
        bytes32(uint256(keccak256("TermMax.storage.GearingNft")) - 1);

    function _getGearingNftStorage()
        internal
        pure
        returns (GearingNftStorage storage s)
    {
        bytes32 slot = STORAGE_SLOT_GEARING_NFT;
        assembly {
            s.slot := slot
        }
    }

    function __AbstractGearingNft_init(
        string memory name,
        string memory symbol,
        address admin,
        GtConfig memory config
    ) internal onlyInitializing {
        __ERC721_init(name, symbol);
        __Ownable_init(admin);
        if (
            config.maxLtv > Constants.DECIMAL_BASE ||
            config.liquidationLtv > Constants.DECIMAL_BASE
        ) {
            revert NumeratorMustLessThanBasicDecimals();
        }
        GearingNftStorage storage s = _getGearingNftStorage();
        s.config = config;
        // Market will burn those tokens after maturity
        config.ft.approve(config.market, UINT_MAX);
    }

    function marketAddr() public view override returns (address) {
        return owner();
    }

    function mint(
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external override returns (uint256 id) {
        GearingNftStorage storage s = _getGearingNftStorage();
        if (msg.sender != s.config.market) {
            revert OnlyMarketCanMintGt();
        }
        _transferCollateralFrom(to, address(this), collateralData);
        id = _mintInternal(to, debtAmt, collateralData, s);
    }

    function _mintInternal(
        address to,
        uint128 debtAmt,
        bytes memory collateralData,
        GearingNftStorage storage s
    ) internal returns (uint256 id) {
        LoanInfo memory loan = LoanInfo(debtAmt, collateralData);
        (uint128 ltv, ) = _calculateLtv(s.config.underlyingOracle, loan);
        if (ltv >= s.config.maxLtv) {
            revert GNftIsNotHealthy(to, debtAmt, ltv, collateralData);
        }
        id = s.total++;
        s.loanMapping[id] = LoanInfo(debtAmt, collateralData);
        _mint(to, id);
    }

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
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
        (ltv, ) = _calculateLtv(s.config.underlyingOracle, loan);
    }

    function _burnInternal(uint256 id, GearingNftStorage storage s) internal {
        _burn(id);
        delete s.loanMapping[id];
    }

    function merge(uint256[] memory ids) external returns (uint256 newId) {
        GearingNftStorage storage s = _getGearingNftStorage();
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
        emit MergeGNfts(msg.sender, newId, ids);
    }

    function repay(
        uint256 id,
        uint128 repayAmt,
        bool byUnderlying
    ) external override nonReentrant {
        GearingNftStorage storage s = _getGearingNftStorage();
        GtConfig memory config = s.config;
        if (byUnderlying) {
            config.underlying.transferFrom(msg.sender, config.market, repayAmt);
        } else {
            // Those ft tokens have been approved to market and will be burn after maturity
            config.ft.transferFrom(msg.sender, address(this), repayAmt);
        }
        _repay(s, msg.sender, id, repayAmt);
        emit Repay(id, repayAmt, byUnderlying);
    }

    function _repay(
        GearingNftStorage storage s,
        address sender,
        uint256 id,
        uint128 repayAmt
    ) internal {
        if (sender != ownerOf(id)) {
            revert SenderIsNotTheOwner(sender, id);
        }
        LoanInfo memory loan = s.loanMapping[id];
        if (repayAmt == loan.debtAmt) {
            // Burn this nft
            _burnInternal(id, s);
            _transferCollateral(sender, loan.collateralData);
        } else {
            s.loanMapping[id].debtAmt -= repayAmt;
        }
    }

    function removeCollateral(
        uint256 id,
        bytes memory collateralData
    ) external override nonReentrant {
        if (msg.sender != ownerOf(id)) {
            revert SenderIsNotTheOwner(msg.sender, id);
        }

        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        loan.collateralData = _removeCollateral(loan, collateralData);

        _transferCollateral(msg.sender, collateralData);

        (uint128 ltv, ) = _calculateLtv(s.config.underlyingOracle, loan);
        if (ltv >= s.config.maxLtv) {
            revert GNftIsNotHealthy(
                msg.sender,
                loan.debtAmt,
                ltv,
                collateralData
            );
        }
        s.loanMapping[id] = loan;

        emit RemoveCollateral(id, loan.collateralData);
    }

    function _removeCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual returns (bytes memory);

    function addCollateral(
        uint256 id,
        bytes memory collateralData
    ) external override nonReentrant {
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];

        _transferCollateralFrom(msg.sender, address(this), collateralData);
        loan.collateralData = _addCollateral(loan, collateralData);

        emit AddCollateral(id, loan.collateralData);
    }

    function _addCollateral(
        LoanInfo memory loan,
        bytes memory collateralData
    ) internal virtual returns (bytes memory);

    function getLiquidationInfo(
        uint256 id
    ) external view returns (bool isLiquidable, uint128 maxRepayAmt) {
        GearingNftStorage storage s = _getGearingNftStorage();
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

    function liquidate(
        uint256 id,
        uint128 repayAmt
    ) external override nonReentrant {
        GearingNftStorage storage s = _getGearingNftStorage();
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
            revert GNftIsSafe(msg.sender, id);
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
            bytes memory remainningCollateralData
        ) = _calcLiquidationResult(loan, repayAmt, valueAndPrice);

        if (repayAmt == loan.debtAmt) {
            if (remainningCollateralData.length > 0) {
                _transferCollateral(ownerOf(id), remainningCollateralData);
            }
            // update storage
            _burnInternal(id, s);
        } else {
            loan.debtAmt -= repayAmt;
            loan.collateralData = remainningCollateralData;
            // Check ltv after partial liquidation
            {
                uint ltvBefore = (valueAndPrice.debtValue *
                    Constants.DECIMAL_BASE) / valueAndPrice.collateralValue;

                uint remainningCollateralValue = _getCollateralValue(
                    remainningCollateralData,
                    valueAndPrice.collateralPriceData
                );
                uint remainningDebtValue = (loan.debtAmt *
                    valueAndPrice.underlyingPrice) /
                    valueAndPrice.priceDecimals;
                if (
                    ltvBefore <
                    ((remainningDebtValue * Constants.DECIMAL_BASE) /
                        remainningCollateralValue)
                ) {
                    revert LtvIncreasedAfterLiquidation(
                        msg.sender,
                        loan.debtAmt,
                        repayAmt,
                        loan.collateralData
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

        emit LiquidateGt(id, msg.sender, repayAmt, cToLiquidator, cToTreasurer, remainningCollateralData);
    }

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
            bytes memory remainningCollateralData
        );

    function _calculateLtv(
        AggregatorV3Interface priceFeed,
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
        ) = _getPrice(priceFeed);
        valueAndPrice.debtValue =
            (loan.debtAmt * valueAndPrice.underlyingPrice) /
            valueAndPrice.priceDecimals;
        ltv = ((valueAndPrice.debtValue * Constants.DECIMAL_BASE) /
            valueAndPrice.collateralValue).toUint128();
    }

    function _getPrice(
        AggregatorV3Interface priceFeed
    ) internal view returns (uint256 price, uint256 decimals) {
        decimals = 10 ** priceFeed.decimals();
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        price = answer.toUint256();
    }

    function _mergeCollateral(
        bytes memory collateralDataA,
        bytes memory collateralDataB
    ) internal virtual returns (bytes memory collateralData);

    function _transferCollateralFrom(
        address from,
        address to,
        bytes memory collateralData
    ) internal virtual;

    function _transferCollateral(
        address to,
        bytes memory collateralData
    ) internal virtual;

    /**
     * @notice This function will return the value of collateral in underlying token unit
     * @param collateralData encoded collateral data
     */
    function _getCollateralValue(
        bytes memory collateralData,
        bytes memory priceData
    ) internal pure virtual returns (uint256 collateralValue);

    function _getCollateralPriceData()
        internal
        view
        virtual
        returns (bytes memory priceData);
}
