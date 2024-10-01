// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./IMintableERC20.sol";

interface IYpToken is IMintableERC20{
    
    function underlying() external view returns(address);

    function maturity() external view returns(uint64);

    function redeem() external;

}