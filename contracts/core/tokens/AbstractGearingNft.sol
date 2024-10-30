// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Constants} from "../lib/Constants.sol";
import {IGearingNft} from "./IGearingNft.sol";

abstract contract AbstractGearingNft is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    ReentrancyGuardUpgradeable,
    IGearingNft
{
    using SafeCast for uint256;
    using SafeCast for int256;

    error CanNotMergeLoanWithDiffOwner();
    error GNftIsHealthy(address liquidator, uint256 id, uint128 healthFactor);
    error GNftIsNotHealthy(
        address owner,
        uint128 debtAmt,
        uint128 healthFactor,
        bytes collateralData
    );
    error GNftIsNotHealthyAfterLiquidation(
        address liquidator,
        uint128 debtAmt,
        uint128 healthFactor,
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

    event RemoveCollateral(uint256 id, bytes newCollateralData);

    event AddCollateral(uint256 id, bytes newCollateralData);

    struct LoanInfo {
        uint128 debtAmt;
        bytes collateralData;
    }
    struct GearingNftStorage {
        address collateral;
        uint256 total;
        uint64 maturity;
        uint128 halfLiquidationThreshold;
        // The loan to collateral of g-nft liquidation threshhold
        uint32 liquidationLtv;
        // The loan to collateral while minting g-nft
        uint32 maxLtv;
        mapping(uint256 => LoanInfo) loanMapping;
    }

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
        address collateral,
        uint128 halfLiquidationThreshold,
        uint64 maturity,
        uint32 maxLtv,
        uint32 liquidationLtv
    ) internal onlyInitializing {
        if (
            maxLtv > Constants.DECIMAL_BASE ||
            liquidationLtv > Constants.DECIMAL_BASE
        ) {
            revert NumeratorMustLessThanBasicDecimals();
        }
        GearingNftStorage storage s = _getGearingNftStorage();
        s.collateral = collateral;
        s.halfLiquidationThreshold = halfLiquidationThreshold;
        s.maturity = maturity;
        s.maxLtv = maxLtv;
        s.liquidationLtv = liquidationLtv;
    }

    function marketAddr() public view override returns (address) {
        return owner();
    }

    function mint(
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external override onlyOwner returns (uint256 id) {
        GearingNftStorage storage s = _getGearingNftStorage();
        _transferCollateralFrom(to, address(this), collateralData);
        id = _mintInternal(to, debtAmt, collateralData, s);
    }

    function _mintInternal(
        address to,
        uint128 debtAmt,
        bytes memory collateralData,
        GearingNftStorage storage s
    ) internal returns (uint256 id) {
        id = s.total++;
        (uint128 healthFactor, ) = calculateHealthFactor(
            debtAmt,
            collateralData
        );
        if (healthFactor >= s.maxLtv) {
            revert GNftIsNotHealthy(to, debtAmt, healthFactor, collateralData);
        }
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
            uint128 healthFactor,
            bytes memory collateralData
        )
    {
        owner = ownerOf(id);
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
        (healthFactor, ) = calculateHealthFactor(debtAmt, collateralData);
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
        address sender,
        uint256 id,
        uint128 repayAmt
    ) external override nonReentrant {
        if (sender != ownerOf(id)) {
            revert SenderIsNotTheOwner(sender, id);
        }
        GearingNftStorage storage s = _getGearingNftStorage();
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

        (uint128 healthFactor, ) = calculateHealthFactor(
            loan.debtAmt,
            loan.collateralData
        );
        if (healthFactor >= s.maxLtv) {
            revert GNftIsNotHealthy(
                msg.sender,
                loan.debtAmt,
                healthFactor,
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
        (isLiquidable, maxRepayAmt) = _getLiquidationInfo(
            id,
            _getGearingNftStorage()
        );
    }

    function _getLiquidationInfo(
        uint256 id,
        GearingNftStorage storage s
    ) internal view returns (bool isLiquidable, uint128 maxRepayAmt) {
        LoanInfo memory loan = s.loanMapping[id];
        (uint128 healthFactor, uint collateralValue) = calculateHealthFactor(
            loan.debtAmt,
            loan.collateralData
        );
        bool isExpired = s.maturity <= block.timestamp;
        isLiquidable = isExpired || healthFactor >= s.liquidationLtv;

        maxRepayAmt = _calculateMaxRepayAmt(
            loan,
            isExpired,
            collateralValue,
            s.halfLiquidationThreshold
        );
    }

    function _calculateMaxRepayAmt(
        LoanInfo memory loan,
        bool isExpired,
        uint256 collateralValue,
        uint128 halfLiquidationThreshold
    ) internal pure returns (uint128 maxRepayAmt) {
        maxRepayAmt = collateralValue < halfLiquidationThreshold || isExpired
            ? loan.debtAmt
            : loan.debtAmt / 2;
    }

    function liquidate(
        uint256 id,
        address liquidator,
        address treasurer,
        uint128 repayAmt
    ) external override nonReentrant {
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        (uint128 healthFactor, uint256 collateralValue) = calculateHealthFactor(
            loan.debtAmt,
            loan.collateralData
        );
        bool isExpired = s.maturity <= block.timestamp;
        uint128 maxRepayAmt = _calculateMaxRepayAmt(
            loan,
            isExpired,
            collateralValue,
            s.halfLiquidationThreshold
        );
        if (repayAmt > maxRepayAmt) {
            revert RepayAmtExceedsMaxRepayAmt(repayAmt, maxRepayAmt);
        }
        if (isExpired || healthFactor >= s.liquidationLtv) {
            bytes memory remainningCollateralData = _liquidate(
                loan,
                liquidator,
                treasurer,
                repayAmt,
                collateralValue
            );
            // Do liquidate
            if (repayAmt == loan.debtAmt) {
                if (remainningCollateralData.length > 0) {
                    _transferCollateral(ownerOf(id), remainningCollateralData);
                }
                _burnInternal(id, s);
            } else {
                loan.debtAmt -= repayAmt;
                loan.collateralData = remainningCollateralData;
                // Check health after partial liquidation
                (healthFactor, ) = calculateHealthFactor(
                    loan.debtAmt,
                    loan.collateralData
                );
                if (healthFactor >= s.liquidationLtv) {
                    revert GNftIsNotHealthyAfterLiquidation(
                        liquidator,
                        loan.debtAmt,
                        healthFactor,
                        loan.collateralData
                    );
                }
            }
        } else {
            revert GNftIsHealthy(liquidator, id, healthFactor);
        }
    }

    function _liquidate(
        LoanInfo memory loan,
        address liquidator,
        address treasurer,
        uint128 repayAmt,
        uint256 collateralValue
    ) internal virtual returns (bytes memory collateralData);

    function calculateHealthFactor(
        uint256 debtAmt,
        bytes memory collateralData
    ) public view returns (uint128 healthFactor, uint256 collateralValue) {
        collateralValue = _getCollateralValue(collateralData);
        healthFactor = ((debtAmt * Constants.DECIMAL_BASE) / collateralValue)
            .toUint128();
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
        bytes memory collateralData
    ) internal view virtual returns (uint256);
}
