// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IYAMarket {
    // bond YpToken, debt YaToken
    function reserves()
        external
        view
        returns (
            uint128 ypAmt,
            uint128 yaAmt,
            uint128 cashAmt,
            uint128 colateralAmt
        );

    // current interest
    function interest() external view returns (uint32);

    // provide liquidity get lp tokens
    function provideLiquidity(
        uint256 cashAmt,
        address lpReceiver
    ) external returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt);

    function swap(
        address tokenIn,
        uint128 amtIn,
        uint128 minAmtOut
    ) external returns (uint256 netAmtOut);

    function withdrawYa(uint128 lpAmtIn) external;

    function withdrawYp(uint128 lpAmtIn) external;
}
