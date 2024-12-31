// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";

interface RouterEvents {
    /// @notice Emitted when setting the market whitelist
    event UpdateMarketWhiteList(address market, bool isWhitelist);

    /// @notice Emitted when setting the swap adapter whitelist
    event UpdateSwapAdapterWhiteList(address adapter, bool isWhitelist);

    event SwapExactTokenToToken(
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        address caller,
        address recipient,
        ITermMaxOrder[] orders,
        uint128[] tradingAmts,
        uint256 actualTokenOut
    );

    event IssueGt(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint128 debtTokenAmtIn,
        uint128 xtAmtIn,
        uint128 ltv,
        bytes collData
    );

    event Borrow(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint256 collInAmt,
        uint128 actualDebtAmt,
        uint128 borrowAmt
    );

    event RepayByTokenThroughFt(
        ITermMaxMarket indexed market,
        uint256 indexed gtId,
        address caller,
        address recipient,
        uint256 totalAmtToBuyFt,
        uint256 returnAmt
    );

    event RedeemAndSwap(
        ITermMaxMarket indexed market,
        uint256 ftAmount,
        address caller,
        address recipient,
        uint256 actualTokenOut
    );

    event CreateOrderAndDeposit(
        ITermMaxMarket indexed market,
        ITermMaxOrder indexed order,
        address maker,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        CurveCuts curveCuts
    );
}
