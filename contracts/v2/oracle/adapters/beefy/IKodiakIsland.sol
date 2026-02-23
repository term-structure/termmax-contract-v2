// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKodiakIsland {
    function totalSupply() external view returns (uint256);
    function getUnderlyingBalances() external view returns (uint256 amount0, uint256 amount1);
    function getUnderlyingBalancesAtPrice(uint160 priceX96) external view returns (uint256 amount0, uint256 amount1);
    function token0() external view returns (address);

    function token1() external view returns (address);

    function burn(uint256 burnAmount, address receiver)
        external
        returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned);
}
