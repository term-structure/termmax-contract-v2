// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {SwapUnit} from "./ISwapAdapter.sol";

/**
 * @title TermMax Router interface
 * @author Term Structure Labs
 */
interface ITermMaxRouter {
    function pause() external;

    function unpause() external;

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
    ) external view returns (IERC20[4] memory tokens, uint256[4] memory balances, address gt, uint256[] memory gtIds);

    /// @notice Swap exact underlying for FT
    /// @param receiver Who receive output tokens
    /// @param market The market's address
    /// @param orders Swap orders
    /// @param tradingAmts Trading amounts
    /// @param minFtOut Expected FT output
    /// @return netFtOut Final FT output
    function swapExactTokenForFt(
        address receiver,
        ITermMaxMarket market,
        ITermMaxOrder[] calldata orders,
        uint256[] calldata tradingAmts,
        uint256 minFtOut
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
    function repay(ITermMaxMarket market, uint256 gtId, uint256 repayAmt) external;

    /// @notice Repay the loan through FT
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param ftInAmt Repay amount
    function repayFromFt(ITermMaxMarket market, uint256 gtId, uint256 ftInAmt) external;

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

    /// @notice Add collateral token to reduce ltv
    /// @param market The market's address
    /// @param gtId The id of loan
    /// @param addCollateralAmt The collateral tokens add to loan
    function addCollateral(ITermMaxMarket market, uint256 gtId, uint256 addCollateralAmt) external;
}
