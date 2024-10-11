// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IYAMarket {
    error MarketIsExpired();

    event ProvideLiquidity(
        address indexed receiver,
        uint256 cashAmount,
        uint128 lpYpAmount,
        uint128 lpYaAmount
    );

    event AddLiquidity(
        address indexed sender,
        uint256 cashAmount,
        uint128 ypMintedAmount,
        uint128 yaMintedAmount
    );

    event WithdrawYP(
        address indexed from,
        uint128 lpYpAmount,
        uint128 ypAmount,
        int64 apy,
        int64 newApy
    );

    event WithdrawYA(
        address indexed from,
        uint128 lpYaAmount,
        uint128 yaAmount,
        int64 apy,
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
        uint256 cashAmt,
        address lpReceiver
    ) external returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt);

    function swap(
        address tokenIn,
        uint128 amtIn,
        uint128 minAmtOut
    ) external returns (uint256 netAmtOut);

    function withdrawYa(uint256 lpAmtIn, address receiver) external;

    // function withdrawYaWithPermit(
    //     uint256 lpAmtIn,
    //     address receiver,
    //     uint256 deadline,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s
    // ) external;

    function withdrawYp(uint256 lpAmtIn, address receiver) external;

    // function withdrawYpWithPermit(
    //     uint256 lpAmtIn,
    //     address receiver,
    //     uint256 deadline,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s
    // ) external;
}
