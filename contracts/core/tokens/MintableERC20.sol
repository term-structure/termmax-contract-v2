// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20PermitUpgradeable, ERC20Upgradeable, IERC20Permit} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMintableERC20} from "./IMintableERC20.sol";

/**
 * @title TermMax ERC20 token
 * @author Term Structure Labs
 */
contract MintableERC20 is
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    IMintableERC20
{
    /// @notice The token's decimals
    uint8 _decimals;

    /**
     * @inheritdoc IMintableERC20
     */
    function initialize(
        address market,
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) public override initializer {
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __Ownable_init(market);
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
        return _decimals;
    }
}
