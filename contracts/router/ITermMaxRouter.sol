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

    /// @notice Emitted when minting GT by leverage or issueFT
    /// @param market The market's address
    /// @param assetIn The input token
    /// @param caller Who provide input token
    /// @param receiver Who receive GT
    /// @param inAmt token input amount
    /// @param xtInAmt XT token input amount to leverage
    /// @param collAmt The collateral token amount in GT
    /// @param ltv The loan to collateral of the GT
    event IssueGt(
        ITermMaxMarket indexed market,
        address indexed assetIn,
        address caller,
        address receiver,
        uint256 gtId,
        uint256 inAmt,
        uint256 xtInAmt,
        uint256 collAmt,
        uint128 ltv
    );

    /// @notice Emitted when redeemming assets from market
    /// @param market The market's address
    /// @param caller Who provide assets
    /// @param receiver Who receive output tokens
    /// @param amountArray token input amounts
    /// @param underlyingOutAmt The underlying token send to receiver
    /// @param collOutAmt The collateral token send to receiver
    event Redeem(
        ITermMaxMarket indexed market,
        address caller,
        address receiver,
        uint256[4] amountArray,
        uint256 underlyingOutAmt,
        uint256 collOutAmt
    );

    /// @notice Emitted when borrowing asset from market
    /// @param market The market's address
    /// @param assetOut The output token
    /// @param caller Who provide collateral asset
    /// @param receiver Who receive output tokens
    /// @param gtId The id of loan
    /// @param collInAmt The collateral token input amount
    /// @param debtAmt The debt amount of the loan
    /// @param borrowAmt The final debt token send to receiver
    event Borrow(
        ITermMaxMarket indexed market,
        address indexed assetOut,
        address caller,
        address receiver,
        uint256 gtId,
        uint256 collInAmt,
        uint256 debtAmt,
        uint256 borrowAmt
    );

    /// @notice Emitted when repaying loan
    /// @param market The market's address
    /// @param isRepayFt Repay using FT or underlying token
    /// @param assetIn The input token to repay loan
    /// @param gtId The id of loan
    /// @param inAmt The input amount
    event Repay(
        ITermMaxMarket indexed market,
        bool indexed isRepayFt,
        address indexed assetIn,
        uint256 gtId,
        uint256 inAmt
    );

    /// @notice Set the pause status of contract
    function togglePause(bool isPause) external;

    /// @notice Set the market whitelist
    /// @param market The market's address
    /// @param isWhitelist Whitelisted or not
    function setMarketWhitelist(address market, bool isWhitelist) external;

    /// @notice Set the adapter whitelist
    /// @param adapter The adapter's address
    /// @param isWhitelist Whitelisted or not
    function setAdapterWhitelist(address adapter, bool isWhitelist) external;

    /// @notice Get assets of the owner
    /// @param market The market's address
    /// @param owner The owner's address
    /// @return tokens The tokens
    /// @return balances The balances of those tokens
    /// @return gt The GT address
    /// @return gtIds The GT ids of the owner
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

    /// @notice Swap exact underlying for FT
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param tokenInAmt The underlying input amount
    /// @param minFtOut Expected FT output
    /// @return netFtOut Final FT output
    function swapExactTokenForFt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minFtOut
    ) external returns (uint256 netFtOut);

    /// @notice Swap exact FT for underlying
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param ftInAmt The FT input amount
    /// @param minTokenOut Expected underlying output
    /// @return netTokenOut Final underlying output
    function swapExactFtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 minTokenOut
    ) external returns (uint256 netTokenOut);

    /// @notice Swap exact underlying for XT
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param tokenInAmt The underlying input amount
    /// @param minXtOut Expected XT output
    /// @return netXtOut Final XT output
    function swapExactTokenForXt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minXtOut
    ) external returns (uint256 netXtOut);

    /// @notice Swap exact XT for underlying
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param xtInAmt The XT input amount
    /// @param minTokenOut Expected underlying output
    /// @return netTokenOut Final underlying output
    function swapExactXtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 minTokenOut
    ) external returns (uint256 netTokenOut);

    /// @notice Withdraw FT and XT token by lp tokens
    /// @param market The market's address
    /// @param receiver Who receive FT and XT token
    /// @param lpFtInAmt LpFT token input amount
    /// @param lpXtInAmt LpXT token input amount
    /// @param minFtOut Expected FT token output amount
    /// @param minXtOut Expected XT token output amount
    /// @return ftOutAmt FT token output amount
    /// @return xtOutAmt XT token output amount
    function withdrawLiquidityToFtXt(
        address receiver,
        ITermMaxMarket market,
        uint256 lpFtInAmt,
        uint256 lpXtInAmt,
        uint256 minFtOut,
        uint256 minXtOut
    ) external returns (uint256 ftOutAmt, uint256 xtOutAmt);

    /// @notice Withdraw underlying token by lp tokens
    /// @param receiver Who receive target token
    /// @param market The market's address
    /// @param lpFtInAmt LpFT token input amount
    /// @param lpXtInAmt LpXT token input amount
    /// @param minTokenOut Expected output amount
    /// @return netTokenOut Final underlying token output
    function withdrawLiquidityToToken(
        address receiver,
        ITermMaxMarket market,
        uint256 lpFtInAmt,
        uint256 lpXtInAmt,
        uint256 minTokenOut
    ) external returns (uint256 netTokenOut);

    /// @notice Redeem assets from market
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param amountArray token input amounts
    /// @param minCollOut Expected collateral output
    /// @param minTokenOut  Expected underlying output
    /// @return netCollOut Final collateral output
    /// @return netTokenOut Final underlying output
    function redeem(
        address receiver,
        ITermMaxMarket market,
        uint256[4] calldata amountArray,
        uint256 minCollOut,
        uint256 minTokenOut
    ) external returns (uint256 netCollOut, uint256 netTokenOut);

    /// @notice Do leverage by underlying token
    /// @param receiver Who receive GT token
    /// @param market The market's address
    /// @param tokenInAmt Underlying token to swap collateral
    /// @param tokenToBuyXtAmt Underlying token to buy XT
    /// @param maxLtv The expected ltv of GT
    /// @param minXtAmt The expected XT amount buying from market
    /// @param units Swap paths to swap underlying to collateral
    /// @return gtId The id of loan
    /// @return netXtOut Final XT token to leverage
    function leverageFromToken(
        address receiver,
        ITermMaxMarket market,
        uint256 tokenInAmt,
        uint256 tokenToBuyXtAmt,
        uint256 maxLtv,
        uint256 minXtAmt,
        SwapUnit[] memory units
    ) external returns (uint256 gtId, uint256 netXtOut);

    /// @notice Do leverage by XT and underlying token
    /// @param receiver Who receive GT token
    /// @param market The market's address
    /// @param xtInAmt XT token to leverage
    /// @param tokenInAmt Underlying token to swap collateral
    /// @param maxLtv The expected ltv of GT
    /// @param units Swap paths to swap underlying to collateral
    /// @return gtId The id of loan
    function leverageFromXt(
        address receiver,
        ITermMaxMarket market,
        uint256 xtInAmt,
        uint256 tokenInAmt,
        uint256 maxLtv,
        SwapUnit[] memory units
    ) external returns (uint256 gtId);

    /// @notice Borrow underlying token from market
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param collInAmt The collateral token input amount
    /// @param maxDebtAmt The maxium debt amount of the loan
    /// @param borrowAmt Debt token send to receiver
    /// @return gtId The id of loan
    function borrowTokenFromCollateral(
        address receiver,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 maxDebtAmt,
        uint256 borrowAmt
    ) external returns (uint256 gtId);

    /// @notice Repay the loan through underlying token
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param repayAmt Repay amount
    function repay(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 repayAmt
    ) external;

    /// @notice Repay the loan through FT
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param ftInAmt Repay amount
    function repayFromFt(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 ftInAmt
    ) external;

    /// @notice Flash repay the loan through collateral
    /// @param receiver Who receive remaming underlying tokens
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param byUnderlying Repay using underlying token or bonds token
    /// @param units Swap paths to swap collateral to underlying
    /// @return netTokenOut Remaming underlying output
    function flashRepayFromColl(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        bool byUnderlying,
        SwapUnit[] memory units
    ) external returns (uint256 netTokenOut);

    /// @notice Repay the loan through FT but input underlying
    /// @param receiver Who receive remaming underlying tokens
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param tokenInAmt Underlying input
    /// @param minFtOutToRepay Minimal FT token buy from market to repay the loan
    function repayByTokenThroughFt(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 tokenInAmt,
        uint256 minFtOutToRepay
    ) external;

    /// @notice Provide liquidity to market
    /// @param receiver Who receive lp tokens
    /// @param market The market's address
    /// @param underlyingAmt Underlying input
    /// @return lpFtOutAmt The LpFT token send to receiver
    /// @return lpXtOutAmt The LpXT token send to receiver
    function provideLiquidity(
        address receiver,
        ITermMaxMarket market,
        uint256 underlyingAmt
    ) external returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt);

    /// @notice Add collateral token to reduce ltv
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param addCollateralAmt The collateral tokens add to loan
    function addCollateral(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 addCollateralAmt
    ) external;
}
