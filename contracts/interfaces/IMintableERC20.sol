// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintableERC20 is IERC20{
    
    function mint(address to, uint256 amount) external;

    function marketAddr() view external returns(address);

    function burn(uint256 amount) external;

}