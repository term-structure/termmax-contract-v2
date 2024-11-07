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

  event Swap(
    ITermMaxMarket indexed market,
    address indexed assetIn,
    address indexed assetOut,
    address caller,
    address receiver,
    uint256 inAmt,
    uint256 outAmt,
    uint256 minOutAmt
  );

  event AddLiquidity(
    ITermMaxMarket indexed market,
    address indexed assetIn,
    address caller,
    address receiver,
    uint256 underlyingInAmt,
    uint256 lpFtOutAmt,
    uint256 lpXtOutAmt
  );

  event WithdrawLiquidityToXtFt(
    ITermMaxMarket indexed market,
    address caller,
    address receiver,
    uint256 lpFtInAmt,
    uint256 lpXtInAmt,
    uint256 ftOutAmt,
    uint256 xtOutAmt,
    uint256 minFtInAmt,
    uint256 minXtInAmt
  );

  event WithdrawLiquidtyToToken(
    ITermMaxMarket indexed market,
    address assetOut,
    address caller,
    address receiver,
    uint256 lpFtInAmt,
    uint256 lpXtInAmt,
    uint256 tokenOutAmt,
    uint256 minTokenOutAmt
  );

  event IssueGt(
    ITermMaxMarket indexed market,
    address indexed assetIn,
    address caller,
    address receiver,
    uint256 gtId,
    uint256 inAmt,
    uint256 xtInAmt,
    // TODO: need collateral
    // uint256 collAmt,
    uint256 minCollAmt,
    uint256 minXTAmt
  );

  event Redeem(
    ITermMaxMarket indexed market,
    address indexed assetOut,
    address caller,
    address receiver,
    uint256[4] amountArray,
    uint256 tokenOutAmt
  );

  event Borrow(
    ITermMaxMarket indexed market,
    address indexed assetOut,
    address caller,
    address receiver,
    uint256 gtId,
    uint256 collInAmt,
    uint256 debtAmt,
    uint256 minDebtAmt
  );

  event Repay(
    ITermMaxMarket indexed market,
    bool indexed isRepayFt,
    address indexed assetIn,
    address caller,
    uint256 gtId,
    uint256 inAmt
  );

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
    ITermMaxMarket market,
    uint256 gtId,
    uint256 ftInAmt
  ) external;

  function repayByTokenThroughFt(
    address receiver,
    ITermMaxMarket market,
    uint256 gtId,
    uint256 tokenInAmt,
    uint256 minFtOutToRepay
  ) external;

}