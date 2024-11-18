// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Permit, ERC20, IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMintableERC20} from "../core/tokens/IMintableERC20.sol";

/**
 * @title TermMax ERC20 token
 * @author Term Structure Labs
 */
contract TestERC20 is ERC20Permit, Ownable, IMintableERC20 {
    string constant DEFAULT_NAME = "TermMax Token";
    string constant DEFAULT_SYMBOL = "TMT";
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor()
        ERC20(DEFAULT_NAME, DEFAULT_SYMBOL)
        Ownable(msg.sender)
        ERC20Permit(DEFAULT_NAME)
    {}

    /**
     * @inheritdoc IMintableERC20
     */
    function initialize(
        address market,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public override {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _transferOwnership(market);
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
     * @inheritdoc ERC20Permit
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
        override(ERC20, IMintableERC20)
        returns (uint8)
    {
        return _decimals;
    }
}
