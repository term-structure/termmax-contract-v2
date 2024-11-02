// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20PermitUpgradeable, ERC20Upgradeable, IERC20Permit} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IMintableERC20} from "./IMintableERC20.sol";

/**
 * @title Term Max ERC20 token
 * @author Term Structure Labs
 */
contract MintableERC20 is
    UUPSUpgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    IMintableERC20
{
    struct MintableERC20Storage {
        /// @notice The token's decimals
        uint8 decimals;
    }

    bytes32 internal constant STORAGE_SLOT_MINTABLE_ERC20 =
        bytes32(uint256(keccak256("TermMax.storage.MintableERC20")) - 1);

    /// @notice Return the storage of this contract
    /// @return s The storage from 'STORAGE_SLOT_MINTABLE_ERC20' slot
    function _getMintableERC20Storage()
        private
        pure
        returns (MintableERC20Storage storage s)
    {
        bytes32 slot = STORAGE_SLOT_MINTABLE_ERC20;
        assembly {
            s.slot := slot
        }
    }

    /// @notice Initial function
    /// @param market The market's address
    /// @param name The token's name
    /// @param symbol The token's symbol
    /// @param _decimals The token's decimals
    function initialize(
        address market,
        string memory name,
        string memory symbol,
        uint8 _decimals
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __Ownable_init(market);
        MintableERC20Storage
            storage mintableStorage = _getMintableERC20Storage();
        mintableStorage.decimals = _decimals;
    }

    /**
     * @inheritdoc IMintableERC20
     */
    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    /**
     * @inheritdoc IMintableERC20
     */
    function marketAddr() public view override returns (address) {
        return owner();
    }

    /**
     * @inheritdoc IMintableERC20
     */
    function burn(uint256 amount) external override onlyOwner {
        _burn(msg.sender, amount);
    }

    /**
     * @inheritdoc ERC20PermitUpgradeable
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        if (spender != marketAddr()) {
            revert SpenderIsNotMarket(spender);
        }
        super.permit(owner, spender, value, deadline, v, r, s);
    }

    /**
     * @inheritdoc IMintableERC20
     */
    function decimals()
        public
        view
        override(ERC20Upgradeable, IMintableERC20)
        returns (uint8)
    {
        MintableERC20Storage
            storage mintableStorage = _getMintableERC20Storage();
        return mintableStorage.decimals;
    }

    /**
     * @inheritdoc UUPSUpgradeable
     */
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}
}
