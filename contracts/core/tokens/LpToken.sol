// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IMintableERC20.sol";

contract LpToken is ERC20Permit, Ownable, IMintableERC20 {
    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    function marketAddr() public view override returns (address) {
        return owner();
    }

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
}
