// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TMX is ERC20{
    /// The total supply of TMX token is 1 billion tokens (1,000,000,000)
    uint256 public constant maxSupply = 1e9 ether;

    constructor(address admin) ERC20("TermMax", "TMX") {
        _mint(admin, maxSupply);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

