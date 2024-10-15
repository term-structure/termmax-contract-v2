// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20} from "../interfaces/IMintableERC20.sol";

interface IYAMarket {
    error MarketIsNotOPen();
    error MarketWasClosed();
    error UnSupportedToken();
    error UnexpectedAmount(
        address sender,
        IMintableERC20 token,
        uint128 expectedAmt,
        uint128 actualAmt
    );

    event ProvideLiquidity(
        address indexed sender,
        uint256 cashAmt,
        uint128 lpYpAmt,
        uint128 lpYaAmt
    );

    event AddLiquidity(
        address indexed sender,
        uint256 cashAmt,
        uint128 ypMintedAmt,
        uint128 yaMintedAmt
    );

    event WithdrawLP(
        address indexed from,
        IMintableERC20 indexed lpToken,
        uint128 lpYpAmt,
        uint128 ypAmt,
        int64 newApy
    );

    event BuyToken(
        address indexed sender,
        IMintableERC20 indexed token,
        uint128 expectedAmt,
        uint128 actualAmt,
        int64 newApy
    );

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

    // current apy
    function apy() external view returns (int64);

    // provide liquidity get lp tokens
    function provideLiquidity(
        uint256 cashAmt
    ) external returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt);

    function withdrawYp(uint256 lpAmtIn) external returns (uint tokenOut);

    function withdrawYa(uint256 lpAmtIn) external returns (uint tokenOut);

    function buyYp(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);

    function buyYa(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external returns (uint256 netOut);
}
