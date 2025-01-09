// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {ITermMaxOrder} from "../ITermMaxOrder.sol";
import {SwapUnit, ISwapAdapter} from "./ISwapAdapter.sol";
import {RouterErrors} from "../errors/RouterErrors.sol";
import {RouterEvents} from "../events/RouterEvents.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";
import {IFlashLoanReceiver} from "../IFlashLoanReceiver.sol";
import {IFlashRepayer} from "../tokens/IFlashRepayer.sol";
import {ITermMaxRouter} from "./ITermMaxRouter.sol";
import {IGearingToken} from "../tokens/IGearingToken.sol";
import {CurveCuts} from "../storage/TermMaxStorage.sol";
import {ISwapCallback} from "../ISwapCallback.sol";

/**
 * @title TermMax Router
 * @author Term Structure Labs
 */
contract TermMaxRouter is
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    IFlashLoanReceiver,
    IFlashRepayer,
    IERC721Receiver,
    ITermMaxRouter,
    RouterErrors,
    RouterEvents
{
    using SafeCast for *;
    using TransferUtils for IERC20;

    /// @notice whitelist mapping of market
    mapping(address => bool) public marketWhitelist;
    /// @notice whitelist mapping of dapter
    mapping(address => bool) public adapterWhitelist;

    /// @notice Check the market is whitelisted
    modifier ensureMarketWhitelist(address market) {
        if (!marketWhitelist[market]) {
            revert MarketNotWhitelisted(market);
        }
        _;
    }
    /// @notice Check the GT is whitelisted
    modifier ensureGtWhitelist(address gt) {
        address market = IGearingToken(gt).marketAddr();
        if (!marketWhitelist[market]) {
            revert MarketNotWhitelisted(market);
        }
        (, , IGearingToken gt_, , ) = ITermMaxMarket(market).tokens();
        if (address(gt_) != gt) {
            revert GtNotWhitelisted(gt);
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __Ownable_init(admin);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function setMarketWhitelist(address market, bool isWhitelist) external onlyOwner {
        marketWhitelist[market] = isWhitelist;
        emit UpdateMarketWhiteList(market, isWhitelist);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function setAdapterWhitelist(address adapter, bool isWhitelist) external onlyOwner {
        adapterWhitelist[adapter] = isWhitelist;
        emit UpdateSwapAdapterWhiteList(adapter, isWhitelist);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function assetsWithERC20Collateral(
        ITermMaxMarket market,
        address owner
    )
        external
        view
        override
        returns (IERC20[4] memory tokens, uint256[4] memory balances, address gtAddr, uint256[] memory gtIds)
    {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) = market.tokens();
        tokens[0] = ft;
        tokens[1] = xt;
        tokens[2] = IERC20(collateral);
        tokens[3] = underlying;
        for (uint i = 0; i < 4; ++i) {
            balances[i] = tokens[i].balanceOf(owner);
        }
        gtAddr = address(gt);
        uint balance = IERC721Enumerable(gtAddr).balanceOf(owner);
        gtIds = new uint256[](balance);
        for (uint i = 0; i < balance; ++i) {
            gtIds[i] = IERC721Enumerable(gtAddr).tokenOfOwnerByIndex(owner, i);
        }
    }

    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 minTokenOut
    ) external whenNotPaused returns (uint256 netTokenOut) {
        uint totalAmtIn = sum(tradingAmts);
        tokenIn.safeTransferFrom(msg.sender, address(this), totalAmtIn);
        netTokenOut = _swapExactTokenToToken(tokenIn, tokenOut, recipient, orders, tradingAmts, minTokenOut);
        emit SwapExactTokenToToken(tokenIn, tokenOut, msg.sender, recipient, orders, tradingAmts, netTokenOut);
    }

    function _swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 minTokenOut
    ) internal returns (uint256 netTokenOut) {
        for (uint256 i = 0; i < orders.length; ++i) {
            ITermMaxOrder order = orders[i];
            tokenIn.safeIncreaseAllowance(address(order), tradingAmts[i]);
            netTokenOut += order.swapExactTokenToToken(tokenIn, tokenOut, recipient, tradingAmts[i], 0);
        }
        if (netTokenOut < minTokenOut) revert InsufficientTokenOut(address(tokenOut), netTokenOut, minTokenOut);
    }

    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 maxTokenIn
    ) external whenNotPaused returns (uint256 netTokenIn) {
        tokenIn.safeTransferFrom(msg.sender, address(this), maxTokenIn);
        netTokenIn = _swapTokenToExactToken(tokenIn, tokenOut, recipient, orders, tradingAmts, maxTokenIn);
        emit SwapTokenToExactToken(tokenIn, tokenOut, msg.sender, recipient, orders, tradingAmts, netTokenIn);
    }

    function _swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 maxTokenIn
    ) internal returns (uint256 netTokenIn) {
        for (uint256 i = 0; i < orders.length; ++i) {
            ITermMaxOrder order = orders[i];
            tokenOut.safeIncreaseAllowance(address(order), maxTokenIn);
            netTokenIn += order.swapTokenToExactToken(tokenIn, tokenOut, recipient, tradingAmts[i], maxTokenIn);
        }
        if (netTokenIn > maxTokenIn) revert InsufficientTokenIn(address(tokenIn), netTokenIn, maxTokenIn);
    }

    function sum(uint128[] memory values) internal pure returns (uint total) {
        for (uint256 i = 0; i < values.length; ++i) {
            total += values[i];
        }
    }

    function sellTokens(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata amtsToSellTokens,
        uint128 minTokenOut
    ) external whenNotPaused ensureMarketWhitelist(address(market)) returns (uint256 netTokenOut) {
        (IERC20 ft, IERC20 xt, , , IERC20 debtToken) = market.tokens();
        (uint maxRedeem, IERC20 toenToSell) = ftInAmt > xtInAmt ? (xtInAmt, ft) : (ftInAmt, xt);

        ft.safeTransferFrom(msg.sender, address(this), ftInAmt);
        ft.safeIncreaseAllowance(address(market), maxRedeem);
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);
        xt.safeIncreaseAllowance(address(market), maxRedeem);
        market.redeem(maxRedeem, recipient);
        netTokenOut = _swapExactTokenToToken(toenToSell, debtToken, recipient, orders, amtsToSellTokens, 0);
        netTokenOut += maxRedeem;
        if (netTokenOut < minTokenOut) revert InsufficientTokenOut(address(debtToken), netTokenOut, minTokenOut);
        emit SellTokens(market, msg.sender, recipient, ftInAmt, xtInAmt, orders, amtsToSellTokens, netTokenOut);
    }

    function leverageFromToken(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata amtsToBuyXt,
        uint128 minXtOut,
        uint128 tokenToSwap,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external whenNotPaused ensureMarketWhitelist(address(market)) returns (uint256 gtId, uint256 netXtOut) {
        (, IERC20 xt, IGearingToken gt, , IERC20 debtToken) = market.tokens();
        uint totalAmtToBuyXt = sum(amtsToBuyXt);
        debtToken.safeTransferFrom(msg.sender, address(this), tokenToSwap + totalAmtToBuyXt);
        netXtOut = _swapExactTokenToToken(debtToken, xt, address(this), orders, amtsToBuyXt, minXtOut);

        bytes memory callbackData = abi.encode(address(gt), tokenToSwap, units);
        xt.safeIncreaseAllowance(address(market), netXtOut);

        gtId = market.leverageByXt(recipient, netXtOut.toUint128(), callbackData);
        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv, ltv);
        }
        emit IssueGt(market, gtId, msg.sender, recipient, tokenToSwap, netXtOut.toUint128(), ltv, collateralData);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function leverageFromXt(
        address recipient,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 tokenInAmt,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external ensureMarketWhitelist(address(market)) whenNotPaused returns (uint256 gtId) {
        (, IERC20 xt, IGearingToken gt, , IERC20 debtToken) = market.tokens();
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);
        xt.safeIncreaseAllowance(address(market), xtInAmt);

        debtToken.safeTransferFrom(msg.sender, address(this), tokenInAmt);

        bytes memory callbackData = abi.encode(address(gt), tokenInAmt, units);
        gtId = market.leverageByXt(recipient, xtInAmt.toUint128(), callbackData);

        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv, ltv);
        }
        emit IssueGt(market, gtId, msg.sender, recipient, tokenInAmt, xtInAmt, ltv, collateralData);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function borrowTokenFromCollateral(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder order,
        uint256 collInAmt,
        uint128 maxDebtAmt,
        uint128 borrowAmt
    ) external ensureMarketWhitelist(address(market)) whenNotPaused returns (uint256 gtId) {
        (IERC20 ft, , IGearingToken gt, address collateralAddr, IERC20 debtToken) = market.tokens();
        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        return _borrow(market, order, ft, gt, debtToken, recipient, collInAmt, maxDebtAmt, borrowAmt);
    }

    function _borrow(
        ITermMaxMarket market,
        ITermMaxOrder order,
        IERC20 ft,
        IGearingToken gt,
        IERC20 debtToken,
        address recipient,
        uint256 collInAmt,
        uint128 maxDebtAmt,
        uint128 borrowAmt
    ) internal returns (uint256) {
        /**
         * 1. MintGT with Collateral, and get GT, FT
         * 2. Sell FT to get UnderlyingToken
         * 3. Transfer UnderlyingToken and GT to Receiver
         */
        (uint256 gtId, uint128 netFtOut) = market.issueFt(
            address(this),
            maxDebtAmt.toUint128(),
            _encodeAmount(collInAmt)
        );

        ft.safeIncreaseAllowance(address(market), netFtOut);
        uint256 netTokenOut = order.swapExactTokenToToken(
            ft,
            debtToken,
            address(this),
            netFtOut,
            borrowAmt.toUint128()
        );
        // NOTE: if netTokenOut > borrowAmt, repay
        uint256 repayAmt = netTokenOut - borrowAmt;
        if (repayAmt > 0) {
            debtToken.safeIncreaseAllowance(address(gt), repayAmt);
            gt.repay(gtId, repayAmt.toUint128(), true);
        }

        debtToken.safeTransfer(recipient, borrowAmt);
        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, (maxDebtAmt - repayAmt).toUint128(), borrowAmt);

        return gtId;
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function flashRepayFromColl(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata amtsToBuyFt,
        bool byUnderlying,
        SwapUnit[] memory units,
        ITermMaxOrder sellFtOrder
    ) external ensureMarketWhitelist(address(market)) whenNotPaused returns (uint256 netTokenOut) {
        (IERC20 ft, , IGearingToken gt, , IERC20 debtToken) = market.tokens();
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        gt.flashRepay(gtId, byUnderlying, abi.encode(orders, amtsToBuyFt, ft, units));
        // SafeTransfer remainning debtToken token
        netTokenOut = debtToken.balanceOf(address(this));
        debtToken.safeTransfer(recipient, netTokenOut);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function repayByTokenThroughFt(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        ITermMaxOrder[] calldata orders,
        uint128[] calldata ftAmtsWantBuy,
        uint128 maxTokenIn
    ) external ensureMarketWhitelist(address(market)) whenNotPaused returns (uint256 returnAmt) {
        (IERC20 ft, , IGearingToken gt, , IERC20 debtToken) = market.tokens();

        debtToken.safeTransferFrom(msg.sender, address(this), maxTokenIn);
        uint256 netCost = _swapExactTokenToToken(debtToken, ft, address(this), orders, ftAmtsWantBuy, maxTokenIn);
        uint totalFtAmt = sum(ftAmtsWantBuy);
        (, uint128 repayAmt, , ) = gt.loanInfo(gtId);

        if (totalFtAmt < repayAmt) {
            repayAmt = totalFtAmt.toUint128();
        }
        gt.repay(gtId, repayAmt, false);

        returnAmt = maxTokenIn - netCost;
        debtToken.safeTransfer(recipient, returnAmt);
        if (totalFtAmt > repayAmt) {
            ft.safeTransfer(recipient, totalFtAmt - repayAmt);
        }

        emit RepayByTokenThroughFt(market, gtId, msg.sender, recipient, repayAmt, returnAmt);
    }

    function redeemAndSwap(
        address recipient,
        ITermMaxMarket market,
        uint256 ftAmount,
        SwapUnit[] memory units,
        uint256 minTokenOut
    ) external ensureMarketWhitelist(address(market)) whenNotPaused returns (uint256 netTokenOut) {
        (IERC20 ft, , , address collateralAddr, IERC20 debtToken) = market.tokens();
        ft.safeTransferFrom(msg.sender, address(this), ftAmount);
        ft.safeIncreaseAllowance(address(market), ftAmount);
        market.redeem(ftAmount, address(this));
        uint deliveredAmt = IERC20(collateralAddr).balanceOf(address(this));
        if (deliveredAmt > 0) {
            netTokenOut = _decodeAmount(_doSwap(_encodeAmount(deliveredAmt), units));
        }
        netTokenOut += debtToken.balanceOf(address(this));
        if (netTokenOut < minTokenOut) {
            revert InsufficientTokenOut(address(debtToken), netTokenOut, minTokenOut);
        }
        debtToken.safeTransfer(recipient, netTokenOut);
        emit RedeemAndSwap(market, ftAmount, msg.sender, recipient, netTokenOut);
    }

    function createOrderAndDeposit(
        ITermMaxMarket market,
        address maker,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        CurveCuts memory curveCuts
    ) external ensureMarketWhitelist(address(market)) whenNotPaused returns (ITermMaxOrder order) {
        (IERC20 ft, IERC20 xt, , , IERC20 debtToken) = market.tokens();
        order = market.createOrder(maker, maxXtReserve, swapTrigger, curveCuts);
        if (debtTokenToDeposit > 0) {
            debtToken.safeTransferFrom(msg.sender, address(this), debtTokenToDeposit);
            debtToken.safeIncreaseAllowance(address(market), debtTokenToDeposit);
            market.mint(address(order), debtTokenToDeposit);
        }
        if (ftToDeposit > 0) {
            ft.safeTransferFrom(msg.sender, address(order), ftToDeposit);
        }
        if (xtToDeposit > 0) {
            xt.safeTransferFrom(msg.sender, address(order), xtToDeposit);
        }

        emit CreateOrderAndDeposit(market, order, maker, debtTokenToDeposit, ftToDeposit, xtToDeposit, curveCuts);
    }

    /// @dev Market flash leverage flashloan callback
    function executeOperation(
        address,
        IERC20,
        uint256 amount,
        bytes calldata data
    ) external ensureMarketWhitelist(msg.sender) returns (bytes memory collateralData) {
        (address gt, uint256 tokenInAmt, SwapUnit[] memory units) = abi.decode(data, (address, uint256, SwapUnit[]));
        uint totalAmount = amount + tokenInAmt;
        collateralData = _doSwap(abi.encode(totalAmount), units);
        SwapUnit memory lastUnit = units[units.length - 1];
        if (!adapterWhitelist[lastUnit.adapter]) {
            revert AdapterNotWhitelisted(lastUnit.adapter);
        }
        // encode collateral data and approve
        bytes memory approvalData = abi.encodeCall(
            ISwapAdapter.approveOutputToken,
            (lastUnit.tokenOut, gt, collateralData)
        );
        (bool success, bytes memory returnData) = lastUnit.adapter.delegatecall(approvalData);
        if (!success) {
            revert ApproveTokenFailWhenSwap(lastUnit.tokenOut, returnData);
        }
    }

    function _balanceOf(IERC20 token, address account) internal view returns (uint256) {
        return token.balanceOf(account);
    }

    function _encodeAmount(uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(amount);
    }

    function _decodeAmount(bytes memory collateralData) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint256));
    }

    /// @dev Gt flash repay flashloan callback
    function executeOperation(
        IERC20 repayToken,
        uint128 debtAmt,
        address,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external override ensureGtWhitelist(msg.sender) {
        (ITermMaxOrder[] memory orders, uint128[] memory amtsToBuyFt, IERC20 ft, SwapUnit[] memory units) = abi.decode(
            callbackData,
            (ITermMaxOrder[], uint128[], IERC20, SwapUnit[])
        );
        // do swap
        bytes memory outData = _doSwap(collateralData, units);

        if (address(repayToken) == address(ft)) {
            IERC20 debtToken = IERC20(units[units.length - 1].tokenOut);
            uint amount = abi.decode(outData, (uint));
            _swapTokenToExactToken(ft, debtToken, address(this), orders, amtsToBuyFt, amount.toUint128());
        }
        repayToken.safeIncreaseAllowance(msg.sender, debtAmt);
    }

    function _doSwap(bytes memory inputData, SwapUnit[] memory units) internal returns (bytes memory outData) {
        for (uint i = 0; i < units.length; ++i) {
            if (!adapterWhitelist[units[i].adapter]) {
                revert AdapterNotWhitelisted(units[i].adapter);
            }
            // encode datas
            bytes memory dataToSwap = abi.encodeCall(
                ISwapAdapter.swap,
                (units[i].tokenIn, units[i].tokenOut, inputData, units[i].swapData)
            );

            // delegatecall
            (bool success, bytes memory returnData) = units[i].adapter.delegatecall(dataToSwap);
            if (!success) {
                revert SwapFailed(units[i].adapter, returnData);
            }
            inputData = abi.decode(returnData, (bytes));
        }
        outData = inputData;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
