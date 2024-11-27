// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../core/ITermMaxMarket.sol";
import {SwapUnit} from "./ISwapAdapter.sol";

/**
 * @title TermMax Router interface
 * @author Term Structure Labs
 */
interface ITermMaxRouter {
    /// @notice Error for calling the market is not whitelisted
    error MarketNotWhitelisted(address market);
    /// @notice Error for calling the gt is not whitelisted
    error GtNotWhitelisted(address gt);
    /// @notice Error for calling the adapter is not whitelisted
    error AdapterNotWhitelisted(address adapter);
    /// @notice Error for the final loan to collateral is bigger than expected
    error LtvBiggerThanExpected(uint128 expectedLtv, uint128 actualLtv);
    /// @notice Error for approving token failed when swapping
    error ApproveTokenFailWhenSwap(address token, bytes revertData);
    /// @notice Error for transfering token failed when swapping
    error TransferTokenFailWhenSwap(address token, bytes revertData);
    /// @notice Error for failed swapping
    error SwapFailed(address adapter, bytes revertData);
    /// @notice Error for the token output is less than expected
    error InsufficientTokenOut(
        address token,
        uint256 expectedTokenOut,
        uint256 actualTokenOut
    );
    /// @notice Emitted when swapping tokens
    /// @param market The market's address
    /// @param assetIn The token to swap
    /// @param assetOut The token want to receive
    /// @param caller Who provide input token
    /// @param receiver Who receive output token
    /// @param inAmt Input amount
    /// @param outAmt Final output amount
    /// @param minOutAmt Expected output amount
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

    /// @notice Emitted when swapping tokens
    /// @param market The market's address
    /// @param assetIn The token to provide liquidity
    /// @param caller Who provide input token
    /// @param receiver Who receive lp tokens
    /// @param underlyingInAmt Underlying token input amount
    /// @param lpFtOutAmt LpFT token output amount
    /// @param lpXtOutAmt LpXT token output amount
    event AddLiquidity(
        ITermMaxMarket indexed market,
        address indexed assetIn,
        address caller,
        address receiver,
        uint256 underlyingInAmt,
        uint256 lpFtOutAmt,
        uint256 lpXtOutAmt
    );

    /// @notice Emitted when withdrawing FT and XT token by lp tokens
    /// @param market The market's address
    /// @param caller Who provide lp tokens
    /// @param receiver Who receive FT and XT token
    /// @param lpFtInAmt LpFT token input amount
    /// @param lpXtInAmt LpXT token input amount
    /// @param ftOutAmt FT token output amount
    /// @param xtOutAmt XT token output amount
    event WithdrawLiquidityToXtFt(
        ITermMaxMarket indexed market,
        address caller,
        address receiver,
        uint256 lpFtInAmt,
        uint256 lpXtInAmt,
        uint256 ftOutAmt,
        uint256 xtOutAmt
    );

    /// @notice Emitted when withdrawing target token by lp tokens
    /// @param market The market's address
    /// @param assetOut The token send to receiver
    /// @param caller Who provide lp tokens
    /// @param receiver Who receive target token
    /// @param lpFtInAmt LpFT token input amount
    /// @param lpXtInAmt LpXT token input amount
    /// @param tokenOutAmt Final target token output
    /// @param minTokenOutAmt Expected output amount
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
        uint256 collAmt,
        uint256 minCollAmt,
        uint256 minXTAmt
    );

    event Redeem(
        ITermMaxMarket indexed market,
        address indexed assetOut,
        address caller,
        address receiver,
        uint256[4] amountArray,
        uint256 tokenOutAmt,
        uint256 collOutAmt
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
        uint256 gtId,
        uint256 inAmt
    );

    function togglePause(bool isPause) external;

    function setMarketWhitelist(address market, bool isWhitelist) external;

    function setAdapterWhitelist(address adapter, bool isWhitelist) external;

    function assetsWithERC20Collateral(
        ITermMaxMarket market,
        address owner
    )
        external
        view
        returns (
            IERC20[6] memory tokens,
            uint256[6] memory balances,
            address gt,
            uint256[] memory gtIds
        );

    function swapExactTokenForFt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minFtOut
    ) external returns (uint256 netFtOut);

    function swapExactFtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 minTokenOut
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
        uint256 minCollOut,
        uint256 minTokenOut
    ) external returns (uint256 netCollOut, uint256 netTokenOut);

    function leverageFromToken(
        address receiver,
        ITermMaxMarket market,
        uint256 tokenInAmt, // underlying to buy collateral
        uint256 tokenToBuyXtAmt, // underlying to buy Xt
        uint256 maxLtv,
        uint256 minXtAmt,
        SwapUnit[] memory units
    ) external returns (uint256 gtId, uint256 netXtOut);

    function leverageFromXt(
        address receiver,
        ITermMaxMarket market,
        uint256 xtInAmt,
        uint256 tokenInAmt,
        uint256 maxLtv,
        SwapUnit[] memory units
    ) external returns (uint256 gtId);

    function borrowTokenFromCollateral(
        address receiver,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 maxDebtAmt,
        uint256 minBorrowAmt
    ) external returns (uint256 gtId);

    function repay(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 repayAmt
    ) external;

    function flashRepayFromColl(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        SwapUnit[] memory units
    ) external returns (uint256 netTokenOut);

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

    function provideLiquidity(
        address receiver,
        ITermMaxMarket market,
        uint256 underlyingAmt
    ) external returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt);

    function addCollateral(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 addCollateralAmt
    ) external;
}
