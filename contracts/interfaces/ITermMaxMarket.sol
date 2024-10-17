// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IMintableERC20, IERC20} from "../interfaces/IMintableERC20.sol";

interface ITermMaxMarket {
    error MarketIsNotOPen();
    error MarketWasClosed();
    error UnSupportedToken();
    error UnexpectedAmount(
        address sender,
        IMintableERC20 token,
        uint128 expectedAmt,
        uint128 actualAmt
    );
    error FlashloanFailedLogString(string);
    error FlashloanFailedLogBytes(bytes);

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

    event SellToken(
        address indexed sender,
        IMintableERC20 indexed token,
        uint128 expectedAmt,
        uint128 actualAmt,
        int64 newApy
    );

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

    // use collateral to mint yp and nft
    function lever(
        uint128 collateralAmt,
        uint128 debtAmt
    ) external returns (uint256 nftId);

    function mintLeveragedNft(
        uint128 collateralAmt,
        uint128 yaAmt
    ) external returns (uint256 nftId);

    // use cash to repayDebt
    function repayDebt(uint256 nftId, uint256 repayAmt) external;

    // can use yp token?
    function liquidate(uint256 nftId) external;

    // use yp to deregister debt
    function deregister(uint256 nftId) external;

    function redeem() external returns (uint256);
}
