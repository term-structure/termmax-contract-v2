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
    error GNftIsHealthy(address liquidator, uint256 id, uint128 health);
    error GNftIsNotHealthy(
        address owner,
        uint128 debtAmt,
        uint128 health,
        bytes collateralData
    );
    error SenderIsNotTheOwner(address sender, uint256 id);

    event MergeGNfts(
        address indexed sender,
        uint256 indexed newId,
        uint256[] ids
    );

    struct LoanInfo {
        uint128 debtAmt;
        bytes collateralData;
    }
    struct GearingNftStorage {
        address collateral;
        uint256 total;
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
        uint32 maxLtv,
        uint32 liquidationLtv
    ) internal onlyInitializing {
        GearingNftStorage storage s = _getGearingNftStorage();
        s.collateral = collateral;
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
        uint128 health = calculateHealth(debtAmt, collateralData);
        if (health >= s.maxLtv) {
            revert GNftIsNotHealthy(to, debtAmt, health, collateralData);
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
            uint128 health,
            bytes memory collateralData
        )
    {
        owner = ownerOf(id);
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
        health = calculateHealth(debtAmt, collateralData);
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

    function deregister(
        address sender,
        uint256 id
    ) external override nonReentrant returns (uint128 debtAmt) {
        if (sender != ownerOf(id)) {
            revert SenderIsNotTheOwner(sender, id);
        }
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        debtAmt = loan.debtAmt;
        _burnInternal(id, s);
        _transferCollateral(sender, loan.collateralData);
    }

    function liquidate(
        uint256 id,
        address liquidator
    ) external override nonReentrant returns (uint128 debtAmt) {
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        uint128 health = calculateHealth(loan.debtAmt, loan.collateralData);
        if (health < s.liquidationLtv) {
            revert GNftIsHealthy(liquidator, id, health);
        }
        debtAmt = loan.debtAmt;
        _burnInternal(id, s);
        _transferCollateral(liquidator, loan.collateralData);
    }

    function calculateHealth(
        uint256 debtAmt,
        bytes memory collateralData
    ) public view returns (uint128 health) {
        uint collateralValue = _sizeCollateralValue(collateralData);
        health = ((debtAmt * Constants.DECIMAL_BASE) / collateralValue)
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

    function _sizeCollateralValue(
        bytes memory collateralData
    ) internal view virtual returns (uint256);
}
