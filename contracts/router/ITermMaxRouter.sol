// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../core/ITermMaxMarket.sol";

enum ContextCallbackType {
  LEVERAGE_FROM_TOKEN,
  LEVERAGE_FROM_XT,
  BORROW_TOKEN_FROM_CASH,
  BORROW_TOKEN_FROM_COLL 
}

struct SwapInput {
  address swapper;
  bytes swapData;
  IERC20 tokenIn;
  IERC20 tokenOut;
}

struct LeverageFromTokenData {
  ITermMaxMarket market;
  address gtAddress;
  uint256 tokenInAmt;
  uint256 minCollAmt;
  uint256 xtInAmt;
  SwapInput swapInput;
}

interface ITermMaxRouter {

  function togglePause(bool isPause) external;
  function setMarketWhitelist(address market, bool isWhitelist) external;
  function setSwapperWhitelist(address swapper, bool isWhitelist) external;

  function swapExactTokenForFt(
    address receiver, ITermMaxMarket market,
    uint128 tokenInAmt, uint128 minFtOut
  ) external returns (uint256 netFtOut);

  function swapExactFtForToken(
    address receiver, ITermMaxMarket market,
    uint128 ftInAmt, uint128 minTokenOut
  ) external returns (uint256 netTokenOut);

  function swapExactTokenForXt(
    address receiver,
    ITermMaxMarket market,
    uint128 tokenInAmt,
    uint128 minXtOut
  ) external returns (uint256 netXtOut);

  function swapExactXtForToken(
    address receiver,
    ITermMaxMarket market,
    uint128 xtInAmt,
    uint128 minTokenOut
  ) external returns (uint256 netTokenOut);

  function withdrawLiquidityToFtXt(
    address receiver,
    ITermMaxMarket market,
    uint256 lpFtInAmt,
    uint256 lpXtInAmt,
    uint256 minFtOut,
    uint256 minXtOut
  ) external returns (uint256 ftOutAmt, uint256 xtOutAmt);

  function withdrawLiquidityToToken(
    address receiver,
    ITermMaxMarket market,
    uint256 lpFtInAmt,
    uint256 lpXtInAmt,
    uint256 minTokenOut
  ) external returns (uint256 netTokenOut);

  function redeem(
    address receiver,
    ITermMaxMarket market,
    uint256[4] calldata amountArray,
    uint256 minTokenOut
  ) external returns (uint256 netOut);

  function leverageFromToken(
    address receiver,
    ITermMaxMarket market,
    uint256 tokenInAmt, // underlying
    uint256 minCollAmt,
    uint256 minXtAmt,
    SwapInput calldata swapInput
  ) external returns (uint256 gtId, uint256 netXtOut);
  
  function leverageFromXt(
    address receiver,
    ITermMaxMarket market,
    uint256 xtInAmt,
    uint256 minCollAmt,
    SwapInput calldata swapInput
  ) external returns (uint256 gtId);

  function borrowTokenFromCollateral(
    address receiver,
    ITermMaxMarket market,
    uint256 collInAmt,
    uint256 debtAmt,
    uint256 minBorrowAmt
  ) external returns (uint256 gtId, uint256 netTokenOut);

  function repayFromFt(
    address beHalf,
    ITermMaxMarket market,
    uint256 gtId,
    uint256 ftInAmt
  ) external;

  function RepayByTokenThroughFt(
    address receiver,
    ITermMaxMarket market,
    uint256 gtId,
    uint256 tokenInAmt,
    uint256 minFtOutToRepay
  ) external;

}