// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IMintableERC20.sol";

contract LpToken is ERC20, Ownable, IMintableERC20{
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender){}

    function mint(address to, uint256 amount) external override onlyOwner{
        _mint(to, amount);
    }

    function marketAddr() public view override returns (address) {
        return owner();
    }

    function burn(uint256 amount) external override{
        _burn(msg.sender, amount);
    }
}