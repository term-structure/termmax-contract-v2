// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {SwapUnit} from "./ISwapAdapter.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";

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

    /// @notice Swap exact token to token
    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata tradingAmts,
        uint128 minTokenOut
    ) external returns (uint256 netTokenOut);

    function leverageFromToken(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata amtsToBuyXt,
        uint128 minXtOut,
        uint128 tokenToSwap,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external returns (uint256 gtId, uint256 netXtOut);

    function leverageFromXt(
        address recipient,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 tokenInAmt,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external returns (uint256 gtId);

    function borrowTokenFromCollateral(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder order,
        uint256 collInAmt,
        uint128 maxDebtAmt,
        uint128 borrowAmt
    ) external returns (uint256 gtId);

    function flashRepayFromColl(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder buyFtOrder,
        uint256 gtId,
        bool byUnderlying,
        SwapUnit[] memory units,
        ITermMaxOrder sellFtOrder
    ) external returns (uint256 netTokenOut);

    function repayByTokenThroughFt(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata amtsToBuyFt,
        uint128 minFtOutToRepay,
        ITermMaxOrder sellFtOrder
    ) external returns (uint256 returnAmt);

    function redeemAndSwap(
        address recipient,
        ITermMaxMarket market,
        uint256 ftAmount,
        SwapUnit[] memory units,
        uint256 minTokenOut
    ) external returns (uint256 netTokenOut);

    function createOrderAndDeposit(
        ITermMaxMarket market,
        address maker,
        uint256 maxXtReserve,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        CurveCuts memory curveCuts
    ) external returns (ITermMaxOrder order);
}
