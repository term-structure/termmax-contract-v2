// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMintableERC20} from "./IMintableERC20.sol";

/**
 * @title TermMax ERC20 token
 * @author Term Structure Labs
 */
contract MintableERC20 is ERC20Upgradeable, OwnableUpgradeable, IMintableERC20 {
    /// @notice The token's decimals
    uint8 _decimals;

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IMintableERC20
     */
    function initialize(string memory name, string memory symbol, uint8 decimals_) public override initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(_msgSender());
        _decimals = decimals_;
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
     * @inheritdoc IMintableERC20
     */
    function decimals() public view override(ERC20Upgradeable, IMintableERC20) returns (uint8) {
        return _decimals;
    }
}
