// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IYARouter{

    // bond YpToken, debt YaToken
    function reserves() external view returns(uint128 bondAmt, uint128 debtAmt);
    // current interest
    function interest() external view returns(uint16);

    // mint ya and yo tokens
    function mint(uint256 debtTokenAmt) external returns(uint128 lpYaOutAmt, uint128 lpYpOutAmt);

    function swap(address tokenIn, uint128 amtIn, uint128 minAmtOut) external returns(uint256 netAmtOut);

    function withdrawYa(uint128 lpAmtIn) external;

    function withdrawYp(uint128 lpAmtIn) external;
}