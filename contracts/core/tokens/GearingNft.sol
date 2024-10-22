// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IGearingNft} from "../../interfaces/IGearingNft.sol";

contract GearingNft is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721Upgradeable,
    IGearingNft
{
    struct LoanInfo {
        uint128 debtAmt;
        bytes collateralData;
    }
    struct GearingNftStorage {
        uint256 total;
        mapping(uint256 => LoanInfo) loanMapping;
    }

    bytes32 internal constant STORAGE_SLOT_GEARING_NFT =
        bytes32(uint256(keccak256("TermMax.storage.GearingNft")) - 1);

    function _getGearingNftStorage()
        private
        pure
        returns (GearingNftStorage storage s)
    {
        bytes32 slot = STORAGE_SLOT_GEARING_NFT;
        assembly {
            s.slot := slot
        }
    }

    function initialize(
        string memory name,
        string memory symbol
    ) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);
    }

    function marketAddr() external view override returns (address) {
        return owner();
    }

    function mint(
        address to,
        uint128 debtAmt,
        bytes memory collateralData
    ) external override onlyOwner returns (uint256 id) {
        GearingNftStorage storage s = _getGearingNftStorage();
        id = _mintInternal(to, debtAmt, collateralData, s);
    }

    function _mintInternal(
        address to,
        uint128 debtAmt,
        bytes memory collateralData,
        GearingNftStorage storage s
    ) internal returns (uint256 id) {
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
        returns (address owner, uint128 debtAmt, bytes memory collateralData)
    {
        owner = ownerOf(id);
        GearingNftStorage storage s = _getGearingNftStorage();
        LoanInfo memory loan = s.loanMapping[id];
        debtAmt = loan.debtAmt;
        collateralData = loan.collateralData;
    }

    function burn(uint256 id) external override onlyOwner {
        GearingNftStorage storage s = _getGearingNftStorage();
        _burnInternal(id, s);
    }

    function _burnInternal(uint256 id, GearingNftStorage storage s) internal {
        _burn(id);
        delete s.loanMapping[id];
    }

    function updateDebt(
        uint256 id,
        uint128 newDebtAmt
    ) external override onlyOwner {
        GearingNftStorage storage s = _getGearingNftStorage();
        s.loanMapping[id].debtAmt = newDebtAmt;
    }

    function _authorizeUpgrade(address) internal virtual override {
        revert UnallowedUpgrade();
    }
}
