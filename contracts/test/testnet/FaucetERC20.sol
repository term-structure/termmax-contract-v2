// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FaucetERC20 is ERC20, Ownable {
    uint8 private immutable _decimals;

    constructor(address adminAddr, string memory name, string memory symbol, uint8 _dec)
        ERC20(name, symbol)
        Ownable(adminAddr)
    {
        _decimals = _dec;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
