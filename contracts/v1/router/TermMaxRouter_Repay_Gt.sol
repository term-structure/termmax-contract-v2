// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
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
import {Constants} from "../lib/Constants.sol";
import {MathLib} from "../lib/MathLib.sol";
import {IGtRepayer} from "./IGtRepayer.sol";

/**
 * @title TermMax Router for GT Repayment
 * @author Term Structure Labs
 * @notice Router contract for repaying GTs
 */
contract TermMaxRouter_Repay_Gt is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    IFlashLoanReceiver,
    IFlashRepayer,
    IERC721Receiver,
    ITermMaxRouter,
    RouterErrors,
    RouterEvents,
    IGtRepayer
{
    using SafeCast for *;
    using TransferUtils for IERC20;
    using MathLib for uint256;

    enum FlashLoanType {
        COLLATERAL,
        DEBT
    }

    /// @notice whitelist mapping of adapter
    mapping(address => bool) public adapterWhitelist;

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __Ownable_init(admin);
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
    function assetsWithERC20Collateral(ITermMaxMarket market, address owner)
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
        for (uint256 i = 0; i < 4; ++i) {
            balances[i] = tokens[i].balanceOf(owner);
        }
        gtAddr = address(gt);
        uint256 balance = IERC721Enumerable(gtAddr).balanceOf(owner);
        gtIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            gtIds[i] = IERC721Enumerable(gtAddr).tokenOfOwnerByIndex(owner, i);
        }
    }

    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 minTokenOut,
        uint256 deadline
    ) external whenNotPaused returns (uint256 netTokenOut) {
        uint256 totalAmtIn = sum(tradingAmts);
        tokenIn.safeTransferFrom(msg.sender, address(this), totalAmtIn);
        netTokenOut = _swapExactTokenToToken(tokenIn, tokenOut, recipient, orders, tradingAmts, minTokenOut, deadline);
        emit SwapExactTokenToToken(tokenIn, tokenOut, msg.sender, recipient, orders, tradingAmts, netTokenOut);
    }

    function _swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 minTokenOut,
        uint256 deadline
    ) internal returns (uint256 netTokenOut) {
        if (orders.length != tradingAmts.length) revert OrdersAndAmtsLengthNotMatch();
        for (uint256 i = 0; i < orders.length; ++i) {
            ITermMaxOrder order = orders[i];
            tokenIn.safeIncreaseAllowance(address(order), tradingAmts[i]);
            netTokenOut += order.swapExactTokenToToken(tokenIn, tokenOut, recipient, tradingAmts[i], 0, deadline);
        }
        if (netTokenOut < minTokenOut) revert InsufficientTokenOut(address(tokenOut), netTokenOut, minTokenOut);
    }

    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 maxTokenIn,
        uint256 deadline
    ) external whenNotPaused returns (uint256 netTokenIn) {
        tokenIn.safeTransferFrom(msg.sender, address(this), maxTokenIn);
        netTokenIn = _swapTokenToExactToken(tokenIn, tokenOut, recipient, orders, tradingAmts, maxTokenIn, deadline);
        tokenIn.safeTransfer(msg.sender, maxTokenIn - netTokenIn);
        emit SwapTokenToExactToken(tokenIn, tokenOut, msg.sender, recipient, orders, tradingAmts, netTokenIn);
    }

    function _swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        ITermMaxOrder[] memory orders,
        uint128[] memory tradingAmts,
        uint128 maxTokenIn,
        uint256 deadline
    ) internal returns (uint256 netTokenIn) {
        if (orders.length != tradingAmts.length) revert OrdersAndAmtsLengthNotMatch();
        for (uint256 i = 0; i < orders.length; ++i) {
            ITermMaxOrder order = orders[i];
            tokenIn.safeIncreaseAllowance(address(order), maxTokenIn);
            netTokenIn +=
                order.swapTokenToExactToken(tokenIn, tokenOut, recipient, tradingAmts[i], maxTokenIn, deadline);
        }
        if (netTokenIn > maxTokenIn) revert InsufficientTokenIn(address(tokenIn), netTokenIn, maxTokenIn);
    }

    function sum(uint128[] memory values) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < values.length; ++i) {
            total += values[i];
        }
    }

    function sellTokens(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        ITermMaxOrder[] memory orders,
        uint128[] memory amtsToSellTokens,
        uint128 minTokenOut,
        uint256 deadline
    ) external whenNotPaused returns (uint256 netTokenOut) {
        (IERC20 ft, IERC20 xt,,, IERC20 debtToken) = market.tokens();
        (uint256 maxBurn, IERC20 toenToSell) = ftInAmt > xtInAmt ? (xtInAmt, ft) : (ftInAmt, xt);

        ft.safeTransferFrom(msg.sender, address(this), ftInAmt);
        ft.safeIncreaseAllowance(address(market), maxBurn);
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);
        xt.safeIncreaseAllowance(address(market), maxBurn);
        market.burn(recipient, maxBurn);
        netTokenOut = _swapExactTokenToToken(toenToSell, debtToken, recipient, orders, amtsToSellTokens, 0, deadline);
        netTokenOut += maxBurn;
        if (netTokenOut < minTokenOut) revert InsufficientTokenOut(address(debtToken), netTokenOut, minTokenOut);
        emit SellTokens(market, msg.sender, recipient, ftInAmt, xtInAmt, orders, amtsToSellTokens, netTokenOut);
    }

    function leverageFromToken(
        address recipient,
        ITermMaxMarket market,
        ITermMaxOrder[] memory orders,
        uint128[] memory amtsToBuyXt,
        uint128 minXtOut,
        uint128 tokenToSwap,
        uint128 maxLtv,
        SwapUnit[] memory units,
        uint256 deadline
    ) external whenNotPaused returns (uint256 gtId, uint256 netXtOut) {
        (, IERC20 xt, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        uint256 totalAmtToBuyXt = sum(amtsToBuyXt);
        debtToken.safeTransferFrom(msg.sender, address(this), tokenToSwap + totalAmtToBuyXt);
        netXtOut = _swapExactTokenToToken(debtToken, xt, address(this), orders, amtsToBuyXt, minXtOut, deadline);

        bytes memory callbackData = abi.encode(address(gt), tokenToSwap, units, FlashLoanType.DEBT);
        xt.safeIncreaseAllowance(address(market), netXtOut);

        gtId = market.leverageByXt(recipient, netXtOut.toUint128(), callbackData);
        (,, bytes memory collateralData) = gt.loanInfo(gtId);
        (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
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
    ) external whenNotPaused returns (uint256 gtId) {
        (, IERC20 xt, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);
        xt.safeIncreaseAllowance(address(market), xtInAmt);

        debtToken.safeTransferFrom(msg.sender, address(this), tokenInAmt);

        bytes memory callbackData = abi.encode(address(gt), tokenInAmt, units, FlashLoanType.DEBT);
        gtId = market.leverageByXt(recipient, xtInAmt.toUint128(), callbackData);

        (,, bytes memory collateralData) = gt.loanInfo(gtId);
        (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv, ltv);
        }
        emit IssueGt(market, gtId, msg.sender, recipient, tokenInAmt, xtInAmt, ltv, collateralData);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function leverageFromXtAndCollateral(
        address recipient,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 collateralInAmt,
        uint128 maxLtv,
        SwapUnit[] memory units
    ) external whenNotPaused returns (uint256 gtId) {
        (, IERC20 xt, IGearingToken gt, address collAddr,) = market.tokens();
        IERC20 collateral = IERC20(collAddr);
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);
        xt.safeIncreaseAllowance(address(market), xtInAmt);

        collateral.safeTransferFrom(msg.sender, address(this), collateralInAmt);

        bytes memory callbackData = abi.encode(address(gt), 0, units, FlashLoanType.COLLATERAL);
        gtId = market.leverageByXt(recipient, xtInAmt.toUint128(), callbackData);

        (,, bytes memory collateralData) = gt.loanInfo(gtId);
        (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv, ltv);
        }
        emit IssueGt(market, gtId, msg.sender, recipient, 0, xtInAmt, ltv, collateralData);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function borrowTokenFromCollateral(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        ITermMaxOrder[] memory orders,
        uint128[] memory tokenAmtsWantBuy,
        uint128 maxDebtAmt,
        uint256 deadline
    ) external whenNotPaused returns (uint256) {
        (IERC20 ft,, IGearingToken gt, address collateralAddr, IERC20 debtToken) = market.tokens();
        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), maxDebtAmt, _encodeAmount(collInAmt));
        uint256 netTokenIn =
            _swapTokenToExactToken(ft, debtToken, recipient, orders, tokenAmtsWantBuy, ftOutAmt, deadline);
        uint256 repayAmt = ftOutAmt - netTokenIn;
        if (repayAmt > 0) {
            ft.safeIncreaseAllowance(address(gt), repayAmt);
            gt.repay(gtId, repayAmt.toUint128(), false);
        }

        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, ftOutAmt, netTokenIn.toUint128());
        return gtId;
    }

    function borrowTokenFromCollateral(address recipient, ITermMaxMarket market, uint256 collInAmt, uint256 borrowAmt)
        external
        whenNotPaused
        returns (uint256)
    {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateralAddr,) = market.tokens();

        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), debtAmt, _encodeAmount(collInAmt));
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);

        ft.safeIncreaseAllowance(address(market), borrowAmt);
        xt.safeIncreaseAllowance(address(market), borrowAmt);

        market.burn(recipient, borrowAmt);

        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, debtAmt, borrowAmt.toUint128());
        return gtId;
    }

    function borrowTokenFromGt(address recipient, ITermMaxMarket market, uint256 gtId, uint256 borrowAmt)
        external
        whenNotPaused
    {
        (IERC20 ft, IERC20 xt, IGearingToken gt,,) = market.tokens();

        if (gt.ownerOf(gtId) != msg.sender) {
            revert GtNotOwnedBySender();
        }

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        uint256 ftOutAmt = market.issueFtByExistedGt(address(this), debtAmt, gtId);
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);

        ft.safeIncreaseAllowance(address(market), borrowAmt);
        xt.safeIncreaseAllowance(address(market), borrowAmt);
        market.burn(recipient, borrowAmt);

        emit Borrow(market, gtId, msg.sender, recipient, 0, debtAmt, borrowAmt.toUint128());
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function flashRepayFromColl(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        ITermMaxOrder[] memory orders,
        uint128[] memory amtsToBuyFt,
        bool byDebtToken,
        SwapUnit[] memory units,
        uint256 deadline
    ) external whenNotPaused returns (uint256 netTokenOut) {
        (IERC20 ft,, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        gt.flashRepay(gtId, byDebtToken, abi.encode(orders, amtsToBuyFt, ft, units, deadline));
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
        ITermMaxOrder[] memory orders,
        uint128[] memory ftAmtsWantBuy,
        uint128 maxTokenIn,
        uint256 deadline
    ) external whenNotPaused returns (uint256 returnAmt) {
        (IERC20 ft,, IGearingToken gt,, IERC20 debtToken) = market.tokens();

        debtToken.safeTransferFrom(msg.sender, address(this), maxTokenIn);
        uint256 netCost =
            _swapTokenToExactToken(debtToken, ft, address(this), orders, ftAmtsWantBuy, maxTokenIn, deadline);
        uint256 totalFtAmt = sum(ftAmtsWantBuy);
        (, uint128 repayAmt,) = gt.loanInfo(gtId);

        if (totalFtAmt < repayAmt) {
            repayAmt = totalFtAmt.toUint128();
        }
        ft.safeIncreaseAllowance(address(gt), repayAmt);
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
    ) external whenNotPaused returns (uint256) {
        (IERC20 ft,,, address collateralAddr, IERC20 debtToken) = market.tokens();
        ft.safeTransferFrom(msg.sender, address(this), ftAmount);
        ft.safeIncreaseAllowance(address(market), ftAmount);
        (uint256 redeemedAmt, bytes memory collateralData) = market.redeem(ftAmount, address(this));
        redeemedAmt += _decodeAmount(_doSwap(collateralData, units));
        if (redeemedAmt < minTokenOut) {
            revert InsufficientTokenOut(address(debtToken), redeemedAmt, minTokenOut);
        }
        debtToken.safeTransfer(recipient, redeemedAmt);
        emit RedeemAndSwap(market, ftAmount, msg.sender, recipient, redeemedAmt);
        return redeemedAmt;
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
    ) external whenNotPaused returns (ITermMaxOrder order) {
        (IERC20 ft, IERC20 xt,,, IERC20 debtToken) = market.tokens();
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
    function executeOperation(address, IERC20, uint256 amount, bytes memory data)
        external
        returns (bytes memory collateralData)
    {
        (address gt, uint256 tokenInAmt, SwapUnit[] memory units, FlashLoanType flashLoanType) =
            abi.decode(data, (address, uint256, SwapUnit[], FlashLoanType));
        uint256 totalAmount = amount + tokenInAmt;
        collateralData = _doSwap(abi.encode(totalAmount), units);
        SwapUnit memory lastUnit = units[units.length - 1];
        if (!adapterWhitelist[lastUnit.adapter]) {
            revert AdapterNotWhitelisted(lastUnit.adapter);
        }

        if (flashLoanType == FlashLoanType.COLLATERAL) {
            IERC20 collateral = IERC20(lastUnit.tokenOut);
            uint256 collateralBalance = collateral.balanceOf(address(this));
            collateralData = _encodeAmount(collateralBalance);
            // approve all collateral if fashloan type is collateral
            collateral.safeIncreaseAllowance(gt, collateralBalance);
        } else if (flashLoanType == FlashLoanType.DEBT) {
            bytes memory approvalData =
                abi.encodeCall(ISwapAdapter.approveOutputToken, (lastUnit.tokenOut, gt, collateralData));
            (bool success, bytes memory returnData) = lastUnit.adapter.delegatecall(approvalData);
            if (!success) {
                revert ApproveTokenFailWhenSwap(lastUnit.tokenOut, returnData);
            }
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
        bytes memory callbackData
    ) external override {
        (
            ITermMaxOrder[] memory orders,
            uint128[] memory amtsToBuyFt,
            IERC20 ft,
            SwapUnit[] memory units,
            uint256 deadline
        ) = abi.decode(callbackData, (ITermMaxOrder[], uint128[], IERC20, SwapUnit[], uint256));
        bytes memory outData = _doSwap(collateralData, units);

        if (address(repayToken) == address(ft)) {
            IERC20 debtToken = IERC20(units[units.length - 1].tokenOut);
            uint256 amount = abi.decode(outData, (uint256));
            _swapTokenToExactToken(debtToken, ft, address(this), orders, amtsToBuyFt, amount.toUint128(), deadline);
        }
        repayToken.safeIncreaseAllowance(msg.sender, debtAmt);
    }

    function _doSwap(bytes memory inputData, SwapUnit[] memory units) internal returns (bytes memory outData) {
        if (units.length == 0) {
            revert SwapUnitsIsEmpty();
        }
        for (uint256 i = 0; i < units.length; ++i) {
            if (!adapterWhitelist[units[i].adapter]) {
                revert AdapterNotWhitelisted(units[i].adapter);
            }
            bytes memory dataToSwap =
                abi.encodeCall(ISwapAdapter.swap, (units[i].tokenIn, units[i].tokenOut, inputData, units[i].swapData));

            (bool success, bytes memory returnData) = units[i].adapter.delegatecall(dataToSwap);
            if (!success) {
                revert SwapFailed(units[i].adapter, returnData);
            }
            inputData = abi.decode(returnData, (bytes));
        }
        outData = inputData;
    }

    function onERC721Received(address, address, uint256, bytes memory) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function repayGt(ITermMaxMarket market, uint256 gtId, uint128 maxRepayAmt, bool byDebtToken)
        external
        override
        whenNotPaused
        returns (uint128 repayAmt)
    {
        (IERC20 ft,, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        (, uint128 debtAmt,) = gt.loanInfo(gtId); // Ensure gtId is valid
        if (maxRepayAmt > debtAmt) {
            repayAmt = debtAmt;
        } else {
            repayAmt = maxRepayAmt;
        }
        IERC20 repayToken = byDebtToken ? debtToken : ft;
        repayToken.safeTransferFrom(msg.sender, address(this), repayAmt);
        repayToken.safeIncreaseAllowance(address(gt), repayAmt);
        gt.repay(gtId, repayAmt, byDebtToken);
    }
}
