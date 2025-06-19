// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {ITermMaxOrder} from "../../v1/ITermMaxOrder.sol";
import {SwapUnit} from "../../v1/router/ISwapAdapter.sol";
import {RouterErrors} from "../../v1/errors/RouterErrors.sol";
import {RouterEvents} from "../../v1/events/RouterEvents.sol";
import {TransferUtils} from "../../v1/lib/TransferUtils.sol";
import {IFlashLoanReceiver} from "../../v1/IFlashLoanReceiver.sol";
import {IFlashRepayer} from "../../v1/tokens/IFlashRepayer.sol";
import {ITermMaxRouterV2, SwapPath} from "./ITermMaxRouterV2.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {IGearingTokenV2} from "../tokens/IGearingTokenV2.sol";
import {CurveCuts, OrderConfig} from "../../v1/storage/TermMaxStorage.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {MathLib} from "../../v1/lib/MathLib.sol";
import {IERC20SwapAdapter} from "./IERC20SwapAdapter.sol";
import {RouterEventsV2} from "../events/RouterEventsV2.sol";

/**
 * @title TermMax Router V2
 * @author Term Structure Labs
 */
contract TermMaxRouterV2 is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    IFlashLoanReceiver,
    IFlashRepayer,
    IERC721Receiver,
    ITermMaxRouterV2,
    RouterErrors,
    RouterEvents
{
    using SafeCast for *;
    using TransferUtils for IERC20;
    using MathLib for uint256;

    enum FlashRepayOptions {
        REPAY,
        ROLLOVER
    }

    /// @notice whitelist mapping of adapter
    mapping(address => bool) public adapterWhitelist;

    uint256 private constant T_ROLLOVER_GT_RESERVE_STORE = 0;

    error SwapPathsIsEmpty();

    modifier checkSwapPaths(SwapPath[] memory paths) {
        if (paths.length == 0 || paths[0].units.length == 0) revert SwapPathsIsEmpty();
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __Ownable_init(admin);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function setAdapterWhitelist(address adapter, bool isWhitelist) external onlyOwner {
        adapterWhitelist[adapter] = isWhitelist;
        emit UpdateSwapAdapterWhiteList(adapter, isWhitelist);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
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

    function swapTokens(SwapPath[] memory paths)
        external
        whenNotPaused
        checkSwapPaths(paths)
        returns (uint256[] memory)
    {
        return _executeSwapPaths(paths);
    }

    function _executeSwapPaths(SwapPath[] memory paths) internal returns (uint256[] memory netTokenOuts) {
        netTokenOuts = new uint256[](paths.length);
        for (uint256 i = 0; i < paths.length; ++i) {
            SwapPath memory path = paths[i];
            if (path.useBalanceOnchain) {
                path.inputAmount = IERC20(path.units[0].tokenIn).balanceOf(address(this));
            } else {
                IERC20(path.units[0].tokenIn).safeTransferFrom(msg.sender, address(this), path.inputAmount);
            }
            netTokenOuts[i] = _executeSwapUnits(path.recipient, path.inputAmount, path.units);
        }
        return netTokenOuts;
    }

    function _executeSwapUnits(address recipient, uint256 inputAmt, SwapUnit[] memory units)
        internal
        returns (uint256 outputAmt)
    {
        if (units.length == 0) {
            revert SwapUnitsIsEmpty();
        }
        for (uint256 i = 0; i < units.length; ++i) {
            if (units[i].tokenIn == units[i].tokenOut) {
                continue;
            }
            if (units[i].adapter == address(0)) {
                // transfer token directly if no adapter is specified
                IERC20(units[i].tokenIn).safeTransfer(recipient, inputAmt);
                continue;
            }
            if (!adapterWhitelist[units[i].adapter]) {
                revert AdapterNotWhitelisted(units[i].adapter);
            }
            bytes memory dataToSwap;
            if (i == units.length - 1) {
                // if it's the last unit and recipient is not this contract, we need to transfer the output token to recipient
                dataToSwap = abi.encodeCall(
                    IERC20SwapAdapter.swap,
                    (recipient, units[i].tokenIn, units[i].tokenOut, inputAmt, units[i].swapData)
                );
            } else {
                dataToSwap = abi.encodeCall(
                    IERC20SwapAdapter.swap,
                    (address(this), units[i].tokenIn, units[i].tokenOut, inputAmt, units[i].swapData)
                );
            }

            (bool success, bytes memory returnData) = units[i].adapter.delegatecall(dataToSwap);
            if (!success) {
                revert SwapFailed(units[i].adapter, returnData);
            }
            inputAmt = abi.decode(returnData, (uint256));
        }
        outputAmt = inputAmt;
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

    /**
     * @inheritdoc ITermMaxRouterV2
     * @dev input/output: =>, swap: ->
     *      path => xt/ft -> debt token => recipient
     */
    function sellFtAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        SwapPath memory path
    ) external whenNotPaused returns (uint256 netTokenOut) {
        (IERC20 ft, IERC20 xt,,,) = market.tokens();
        uint256 maxBurn = ftInAmt > xtInAmt ? xtInAmt : ftInAmt;
        ft.transferFrom(msg.sender, address(this), ftInAmt);
        xt.transferFrom(msg.sender, address(this), xtInAmt);
        ft.safeIncreaseAllowance(address(market), maxBurn);
        xt.safeIncreaseAllowance(address(market), maxBurn);
        market.burn(recipient, maxBurn);
        netTokenOut = maxBurn + _executeSwapUnits(path.recipient, path.inputAmount, path.units);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function sellFtAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 xtInAmt,
        SwapPath memory path
    ) external whenNotPaused returns (uint256 netTokenOut) {
        uint256 maxBurn = ftInAmt > xtInAmt ? xtInAmt : ftInAmt;
        ITermMaxMarketV2(address(market)).burn(msg.sender, recipient, maxBurn);
        IERC20 tokenIn = IERC20(path.units[0].tokenIn);
        tokenIn.safeTransferFrom(msg.sender, address(this), path.inputAmount);
        netTokenOut = maxBurn + _executeSwapUnits(path.recipient, path.inputAmount, path.units);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function leverageForV1(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
        SwapPath[] memory inputPaths,
        SwapPath memory swapCollateralPath
    ) external whenNotPaused returns (uint256 gtId, uint256 netXtOut) {
        (, IERC20 xt, IGearingToken gt,,) = market.tokens();
        netXtOut = _executeSwapPaths(inputPaths)[0];
        xt.safeIncreaseAllowance(address(market), netXtOut);

        bytes memory callbackData = abi.encode(address(gt), swapCollateralPath.units);
        gtId =
            ITermMaxMarketV2(address(market)).leverageByXt(address(this), recipient, netXtOut.toUint128(), callbackData);
        (,, bytes memory collateralData) = gt.loanInfo(gtId);
        (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv, ltv);
        }
        emit IssueGt(
            market,
            gtId,
            msg.sender,
            recipient,
            (inputPaths[1].inputAmount).toUint128(),
            netXtOut.toUint128(),
            ltv,
            collateralData
        );
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function leverageForV2(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
        SwapPath[] memory inputPaths,
        SwapPath memory swapCollateralPath
    ) external whenNotPaused returns (uint256 gtId, uint256 netXtOut) {
        (,, IGearingToken gt,,) = market.tokens();
        netXtOut = _executeSwapPaths(inputPaths)[0];

        bytes memory callbackData = abi.encode(address(gt), swapCollateralPath.units);
        gtId =
            ITermMaxMarketV2(address(market)).leverageByXt(address(this), recipient, netXtOut.toUint128(), callbackData);
        (,, bytes memory collateralData) = gt.loanInfo(gtId);
        (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv, ltv);
        }
        emit IssueGt(
            market,
            gtId,
            msg.sender,
            recipient,
            (inputPaths[1].inputAmount).toUint128(),
            netXtOut.toUint128(),
            ltv,
            collateralData
        );
    }

    function borrowTokenFromCollateral(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint128 maxDebtAmt,
        SwapPath memory swapFtPath
    ) external whenNotPaused returns (uint256) {
        (IERC20 ft,, IGearingToken gt, address collateralAddr,) = market.tokens();
        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), maxDebtAmt, _encodeAmount(collInAmt));
        uint256 netTokenIn = _executeSwapUnits(swapFtPath.recipient, ftOutAmt, swapFtPath.units);
        uint256 repayAmt = ftOutAmt - netTokenIn;
        if (repayAmt > 0) {
            ft.safeIncreaseAllowance(address(gt), repayAmt);
            gt.repay(gtId, repayAmt.toUint128(), false);
        }

        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, ftOutAmt, netTokenIn.toUint128());
        return gtId;
    }

    function borrowTokenFromCollateralAndXtForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt
    ) external whenNotPaused returns (uint256) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateralAddr,) = market.tokens();

        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), debtAmt, _encodeAmount(collInAmt));
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);
        xt.safeIncreaseAllowance(address(market), borrowAmt);
        ft.safeIncreaseAllowance(address(market), borrowAmt);
        market.burn(recipient, borrowAmt);

        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, debtAmt, borrowAmt.toUint128());
        return gtId;
    }

    function borrowTokenFromCollateralAndXtForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt
    ) external whenNotPaused returns (uint256) {
        (, IERC20 xt, IGearingToken gt, address collateralAddr,) = market.tokens();

        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), debtAmt, _encodeAmount(collInAmt));
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);
        ITermMaxMarketV2(address(market)).burn(address(this), recipient, borrowAmt);

        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, debtAmt, borrowAmt.toUint128());
        return gtId;
    }

    function borrowTokenFromGtAndXtForV1(address recipient, ITermMaxMarket market, uint256 gtId, uint256 borrowAmt)
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
        xt.safeIncreaseAllowance(address(market), borrowAmt);
        ft.safeIncreaseAllowance(address(market), borrowAmt);
        market.burn(recipient, borrowAmt);

        emit Borrow(market, gtId, msg.sender, recipient, 0, debtAmt, borrowAmt.toUint128());
    }

    function borrowTokenFromGtAndXtForV2(address recipient, ITermMaxMarket market, uint256 gtId, uint256 borrowAmt)
        external
        whenNotPaused
    {
        (, IERC20 xt, IGearingToken gt,,) = market.tokens();

        if (gt.ownerOf(gtId) != msg.sender) {
            revert GtNotOwnedBySender();
        }

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        uint256 ftOutAmt = market.issueFtByExistedGt(address(this), debtAmt, gtId);
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);

        ITermMaxMarketV2(address(market)).burn(address(this), recipient, borrowAmt);

        emit Borrow(market, gtId, msg.sender, recipient, 0, debtAmt, borrowAmt.toUint128());
    }

    function flashRepayFromCollForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        SwapPath[] memory swapPaths
    ) external whenNotPaused returns (uint256 netTokenOut) {
        (,, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        bytes memory callbackData = abi.encode(swapPaths);
        callbackData = abi.encode(FlashRepayOptions.REPAY, callbackData);
        gt.flashRepay(gtId, byDebtToken, callbackData);
        netTokenOut = debtToken.balanceOf(address(this));
        debtToken.safeTransfer(recipient, netTokenOut);
    }

    function flashRepayFromCollForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        bool byDebtToken,
        bytes memory removedCollateral,
        SwapPath[] memory swapPaths
    ) external whenNotPaused returns (uint256 netTokenOut) {
        (,, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        bytes memory callbackData = abi.encode(swapPaths);
        callbackData = abi.encode(FlashRepayOptions.REPAY, callbackData);
        bool repayAll =
            IGearingTokenV2(address(gt)).flashRepay(gtId, repayAmt, byDebtToken, removedCollateral, callbackData);
        if (!repayAll) {
            gt.safeTransferFrom(address(this), msg.sender, gtId);
        }
        netTokenOut = debtToken.balanceOf(address(this));
        debtToken.safeTransfer(recipient, netTokenOut);
    }

    // /**
    //  * @inheritdoc ITermMaxRouterV2
    //  * path0: debt token-> ft
    //  * path1: remaining debt -> recipient
    //  */
    function repayByTokenThroughFt(address recipient, ITermMaxMarket market, uint256 gtId, SwapPath[] memory paths)
        external
        whenNotPaused
        returns (uint256 netCost)
    {
        netCost = _executeSwapPaths(paths)[0];
        (IERC20 ft,, IGearingToken gt,,) = market.tokens();
        uint256 repayAmt = ft.balanceOf(address(this));

        ft.safeIncreaseAllowance(address(gt), repayAmt);
        gt.repay(gtId, repayAmt.toUint128(), false);

        emit RouterEventsV2.RepayByTokenThroughFt(address(market), gtId, msg.sender, recipient, repayAmt, netCost);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function redeemAndSwap(
        address recipient,
        ITermMaxMarket market,
        uint256 ftAmount,
        SwapUnit[] memory units,
        uint256 minTokenOut
    ) external whenNotPaused returns (uint256) {
        (,,,, IERC20 debtToken) = market.tokens();
        (uint256 redeemedAmt, bytes memory collateralData) =
            ITermMaxMarketV2(address(market)).redeem(msg.sender, address(this), ftAmount);
        redeemedAmt += _doSwap(_decodeAmount(collateralData), units);
        if (redeemedAmt < minTokenOut) {
            revert InsufficientTokenOut(address(debtToken), redeemedAmt, minTokenOut);
        }
        debtToken.safeTransfer(recipient, redeemedAmt);
        emit RedeemAndSwap(market, ftAmount, msg.sender, recipient, redeemedAmt);
        return redeemedAmt;
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function placeOrderForV1(
        ITermMaxMarket market,
        address maker,
        uint256 collateralToMintGt,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        OrderConfig memory orderConfig
    ) external whenNotPaused returns (ITermMaxOrder order, uint256 gtId) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 debtToken) = market.tokens();
        if (collateralToMintGt > 0) {
            IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralToMintGt);
            IERC20(collateral).safeIncreaseAllowance(address(gt), collateralToMintGt);
            (gtId,) = market.issueFt(maker, 0, _encodeAmount(collateralToMintGt));
        }
        order = market.createOrder(maker, orderConfig.maxXtReserve, orderConfig.swapTrigger, orderConfig.curveCuts);

        if (debtTokenToDeposit > 0) {
            debtToken.safeTransferFrom(msg.sender, address(this), debtTokenToDeposit);
            debtToken.safeIncreaseAllowance(address(market), debtTokenToDeposit);
            market.mint(address(order), debtTokenToDeposit);
        }
        ft.safeTransferFrom(msg.sender, address(order), ftToDeposit);
        xt.safeTransferFrom(msg.sender, address(order), xtToDeposit);
        emit RouterEventsV2.PlaceOrder(maker, address(order), address(market), gtId, orderConfig);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function placeOrderForV2(
        ITermMaxMarket market,
        address maker,
        uint256 collateralToMintGt,
        uint256 debtTokenToDeposit,
        uint128 ftToDeposit,
        uint128 xtToDeposit,
        OrderConfig memory orderConfig
    ) external whenNotPaused returns (ITermMaxOrder order, uint256 gtId) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateral, IERC20 debtToken) = market.tokens();
        if (collateralToMintGt > 0) {
            IERC20(collateral).safeTransferFrom(msg.sender, address(this), collateralToMintGt);
            IERC20(collateral).safeIncreaseAllowance(address(gt), collateralToMintGt);
            (orderConfig.gtId,) = market.issueFt(maker, 0, _encodeAmount(collateralToMintGt));
        }
        order = ITermMaxMarketV2(address(market)).createOrder(maker, orderConfig);

        if (debtTokenToDeposit > 0) {
            debtToken.safeTransferFrom(msg.sender, address(this), debtTokenToDeposit);
            debtToken.safeIncreaseAllowance(address(market), debtTokenToDeposit);
            market.mint(address(order), debtTokenToDeposit);
        }
        ft.safeTransferFrom(msg.sender, address(order), ftToDeposit);
        xt.safeTransferFrom(msg.sender, address(order), xtToDeposit);
        emit RouterEventsV2.PlaceOrder(maker, address(order), address(market), gtId, orderConfig);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function rolloverGt(
        address recipient,
        IGearingToken gt,
        uint256 gtId,
        uint128 additionalAssets,
        SwapUnit[] memory units,
        ITermMaxMarket nextMarket,
        uint256 additionnalNextCollateral,
        TermMaxSwapData memory swapData,
        uint128 maxLtv
    ) external whenNotPaused returns (uint256 newGtId) {
        // clear ts stograge
        assembly {
            tstore(T_ROLLOVER_GT_RESERVE_STORE, 0)
        }
        // additional debt token to reduce the ltv
        if (additionalAssets != 0) {
            IERC20(swapData.tokenOut).safeTransferFrom(msg.sender, address(this), additionalAssets);
        }
        // additional collateral to reduce the ltv
        if (additionnalNextCollateral != 0) {
            IERC20(units[units.length - 1].tokenOut).safeTransferFrom(
                msg.sender, address(this), additionnalNextCollateral
            );
        }
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        bytes memory callbackData =
            abi.encode(recipient, maxLtv, additionalAssets, nextMarket, additionnalNextCollateral, units, swapData);
        callbackData = abi.encode(FlashRepayOptions.ROLLOVER, callbackData);
        gt.flashRepay(gtId, true, callbackData);
        assembly {
            newGtId := tload(T_ROLLOVER_GT_RESERVE_STORE)
        }
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function rolloverGtV2(
        address recipient,
        IGearingToken gt,
        uint256 gtId,
        uint128 repayAmt,
        uint128 additionalAssets,
        uint256 removedCollateral,
        SwapUnit[] memory units,
        ITermMaxMarket nextMarket,
        uint256 additionnalNextCollateral,
        TermMaxSwapData memory swapData,
        uint128 maxLtv
    ) external whenNotPaused returns (uint256 newGtId) {
        // clear ts stograge
        assembly {
            tstore(T_ROLLOVER_GT_RESERVE_STORE, 0)
        }
        // additional debt token to reduce the ltv
        if (additionalAssets != 0) {
            IERC20(swapData.tokenOut).safeTransferFrom(msg.sender, address(this), additionalAssets);
        }
        // additional collateral to reduce the ltv
        if (additionnalNextCollateral != 0) {
            IERC20(units[units.length - 1].tokenOut).safeTransferFrom(
                msg.sender, address(this), additionnalNextCollateral
            );
        }
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        bytes memory callbackData =
            abi.encode(recipient, maxLtv, additionalAssets, nextMarket, additionnalNextCollateral, units, swapData);
        callbackData = abi.encode(FlashRepayOptions.ROLLOVER, callbackData);
        if (!IGearingTokenV2(address(gt)).flashRepay(gtId, repayAmt, true, abi.encode(removedCollateral), callbackData))
        {
            gt.safeTransferFrom(address(this), recipient, gtId);
        }
        assembly {
            newGtId := tload(T_ROLLOVER_GT_RESERVE_STORE)
        }
    }

    /// @dev Market flash leverage flashloan callback
    function executeOperation(address, IERC20, uint256, bytes memory data)
        external
        returns (bytes memory collateralData)
    {
        (address gt, SwapUnit[] memory units) = abi.decode(data, (address, SwapUnit[]));
        uint256 totalAmount = IERC20(units[0].tokenIn).balanceOf(address(this));
        uint256 collateralBalance = _doSwap(totalAmount, units);
        SwapUnit memory lastUnit = units[units.length - 1];
        if (!adapterWhitelist[lastUnit.adapter]) {
            revert AdapterNotWhitelisted(lastUnit.adapter);
        }
        IERC20 collateral = IERC20(lastUnit.tokenOut);
        collateralBalance = collateral.balanceOf(address(this));
        collateral.safeIncreaseAllowance(gt, collateralBalance);
        collateralData = _encodeAmount(collateralBalance);
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
        uint128 repayAmt,
        address,
        bytes memory removedCollateralData,
        bytes memory callbackData
    ) external override {
        (FlashRepayOptions option, bytes memory data) = abi.decode(callbackData, (FlashRepayOptions, bytes));
        if (option == FlashRepayOptions.REPAY) {
            _flashRepay(data);
        } else if (option == FlashRepayOptions.ROLLOVER) {
            _rollover(repayToken, repayAmt, removedCollateralData, data);
        }
        repayToken.safeIncreaseAllowance(msg.sender, repayAmt);
    }

    function _flashRepay(bytes memory callbackData) internal {
        (SwapPath[] memory swapPaths) = abi.decode(callbackData, (SwapPath[]));
        _executeSwapPaths(swapPaths);
    }

    function _rollover(IERC20 debtToken, uint256 debtAmt, bytes memory collateralData, bytes memory callbackData)
        internal
    {
        (
            address recipient,
            uint128 maxLtv,
            uint128 additionalAssets,
            ITermMaxMarket market,
            uint256 additionnalNextCollateral,
            SwapUnit[] memory units,
            TermMaxSwapData memory swapData
        ) = abi.decode(callbackData, (address, uint128, uint128, ITermMaxMarket, uint256, SwapUnit[], TermMaxSwapData));
        {
            // swap collateral
            collateralData =
                units.length == 0 ? collateralData : _encodeAmount(_doSwap(_decodeAmount(collateralData), units));
        }
        (IERC20 ft,, IGearingToken gt, address collateral,) = market.tokens();
        uint256 gtId;
        {
            // issue new gt
            uint256 mintGtFeeRatio = market.mintGtFeeRatio();
            uint128 newDebtAmt = (
                (swapData.netTokenAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)
            ).toUint128();
            uint256 newCollateralAmt = _decodeAmount(collateralData) + additionnalNextCollateral;
            IERC20(collateral).safeIncreaseAllowance(address(gt), newCollateralAmt);
            (gtId,) = market.issueFt(address(this), newDebtAmt, abi.encode(newCollateralAmt));
        }
        {
            uint256 netFtIn = _swapTokenToExactToken(
                ft,
                debtToken,
                address(this),
                swapData.orders,
                swapData.tradingAmts,
                swapData.netTokenAmt,
                swapData.deadline
            );
            // check remaining ft amount
            if (swapData.netTokenAmt > netFtIn) {
                uint256 repaidFtAmt = swapData.netTokenAmt - netFtIn;
                ft.safeIncreaseAllowance(address(gt), repaidFtAmt);
                gt.repay(gtId, repaidFtAmt.toUint128(), false);
            }
            // check remaining debt token amount
            uint256 totalDebtTokenAmt = sum(swapData.tradingAmts) + additionalAssets;
            if (totalDebtTokenAmt > debtAmt) {
                uint256 repaidDebtAmt = totalDebtTokenAmt - debtAmt;
                debtToken.safeIncreaseAllowance(address(gt), repaidDebtAmt);
                gt.repay(gtId, repaidDebtAmt.toUint128(), true);
            }
            (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
            if (ltv > maxLtv) {
                revert LtvBiggerThanExpected(maxLtv, ltv);
            }
        }
        // transfer new gt to recipient
        gt.safeTransferFrom(address(this), recipient, gtId);
        assembly {
            tstore(T_ROLLOVER_GT_RESERVE_STORE, gtId)
        }
    }

    function _doSwap(uint256 inputAmt, SwapUnit[] memory units) internal returns (uint256 outputAmt) {
        if (units.length == 0) {
            revert SwapUnitsIsEmpty();
        }
        for (uint256 i = 0; i < units.length; ++i) {
            if (!adapterWhitelist[units[i].adapter]) {
                revert AdapterNotWhitelisted(units[i].adapter);
            }
            bytes memory dataToSwap = abi.encodeCall(
                IERC20SwapAdapter.swap,
                (address(this), units[i].tokenIn, units[i].tokenOut, inputAmt, units[i].swapData)
            );

            (bool success, bytes memory returnData) = units[i].adapter.delegatecall(dataToSwap);
            if (!success) {
                revert SwapFailed(units[i].adapter, returnData);
            }
            inputAmt = abi.decode(returnData, (uint256));
        }
        outputAmt = inputAmt;
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
}
