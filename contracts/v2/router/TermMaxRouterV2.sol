// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {SwapUnit} from "../../v1/router/ISwapAdapter.sol";
import {RouterErrors} from "../../v1/errors/RouterErrors.sol";
import {RouterEvents} from "../../v1/events/RouterEvents.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {IFlashLoanReceiver} from "../../v1/IFlashLoanReceiver.sol";
import {IFlashRepayer} from "../../v1/tokens/IFlashRepayer.sol";
import {ITermMaxRouterV2, SwapPath, IERC4626, FlashLoanType, FlashRepayOptions} from "./ITermMaxRouterV2.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {IGearingTokenV2} from "../tokens/IGearingTokenV2.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {IERC20SwapAdapter} from "./IERC20SwapAdapter.sol";
import {IAaveV3PoolMinimal} from "../extensions/aave/IAaveV3PoolMinimal.sol";
import {IMorpho, MarketParams, Id} from "../extensions/morpho/IMorpho.sol";
import {RouterErrorsV2} from "../errors/RouterErrorsV2.sol";
import {ArrayUtilsV2} from "../lib/ArrayUtilsV2.sol";
import {VersionV2} from "../VersionV2.sol";
import {CurveCuts, OrderConfig} from "../../v1/storage/TermMaxStorage.sol";
import {OrderInitialParams} from "../ITermMaxOrderV2.sol";

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
    RouterEvents,
    VersionV2
{
    using SafeCast for *;
    using TransferUtilsV2 for IERC20;
    using Math for *;
    using ArrayUtilsV2 for *;

    /// @notice whitelist mapping of adapter
    mapping(address => bool) public adapterWhitelist;

    uint256 private constant T_ROLLOVER_GT_RESERVE_STORE = 0;
    uint256 private constant T_CALLBACK_ADDRESS_STORE = 1;

    modifier onlyCallbackAddress() {
        address callbackAddress;
        assembly {
            callbackAddress := tload(T_CALLBACK_ADDRESS_STORE)
        }
        if (msg.sender != callbackAddress) {
            revert RouterErrorsV2.CallbackAddressNotMatch();
        }
        _;
        assembly {
            // clear callback address after use
            tstore(T_CALLBACK_ADDRESS_STORE, 0)
        }
    }

    modifier checkSwapPaths(SwapPath[] memory paths) {
        if (paths.length == 0 || paths[0].units.length == 0) revert RouterErrorsV2.SwapPathsIsEmpty();
        _;
    }

    modifier noCallbackReentrant() {
        address callbackAddress;
        assembly {
            callbackAddress := tload(T_CALLBACK_ADDRESS_STORE)
        }
        if (callbackAddress != address(0)) {
            revert RouterErrorsV2.CallbackReentrant();
        }
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();
        __Ownable_init_unchained(admin);
    }

    function setAdapterWhitelist(address adapter, bool isWhitelist) external onlyOwner {
        adapterWhitelist[adapter] = isWhitelist;
        emit UpdateSwapAdapterWhiteList(adapter, isWhitelist);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
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

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function leverage(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
        bool isV1,
        SwapPath[] memory inputPaths,
        SwapPath memory swapCollateralPath
    ) external whenNotPaused noCallbackReentrant returns (uint256 gtId, uint256 netXtOut) {
        assembly {
            tstore(T_CALLBACK_ADDRESS_STORE, market) // set callback address
        }
        (, IERC20 xt, IGearingToken gt,,) = market.tokens();
        netXtOut = _executeSwapPaths(inputPaths)[0];
        bytes memory callbackData = abi.encode(address(gt), swapCollateralPath.units);
        if (isV1) {
            xt.safeIncreaseAllowance(address(market), netXtOut);
            gtId = market.leverageByXt(recipient, netXtOut.toUint128(), callbackData);
        } else {
            gtId = ITermMaxMarketV2(address(market)).leverageByXt(
                address(this), recipient, netXtOut.toUint128(), callbackData
            );
        }

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

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), maxDebtAmt, abi.encode(collInAmt));
        uint256 netTokenIn = _executeSwapUnits(swapFtPath.recipient, ftOutAmt, swapFtPath.units);
        uint256 repayAmt = ftOutAmt - netTokenIn;
        if (repayAmt > 0) {
            ft.safeIncreaseAllowance(address(gt), repayAmt);
            // repay in ft, bool false means not using debt token
            gt.repay(gtId, repayAmt.toUint128(), false);
        }

        gt.safeTransferFrom(address(this), recipient, gtId);
        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, ftOutAmt, netTokenIn.toUint128());
        return gtId;
    }

    function borrowTokenFromCollateralAndXt(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt,
        bool isV1
    ) external whenNotPaused returns (uint256) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateralAddr,) = market.tokens();

        IERC20(collateralAddr).safeTransferFrom(msg.sender, address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), debtAmt, abi.encode(collInAmt));
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);
        if (isV1) {
            xt.safeIncreaseAllowance(address(market), borrowAmt);
            ft.safeIncreaseAllowance(address(market), borrowAmt);
        }

        market.burn(recipient, borrowAmt);
        gt.safeTransferFrom(address(this), recipient, gtId);

        emit Borrow(market, gtId, msg.sender, recipient, collInAmt, debtAmt, borrowAmt.toUint128());
        return gtId;
    }

    function borrowTokenFromGtAndXt(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 borrowAmt,
        bool isV1
    ) external whenNotPaused {
        (IERC20 ft, IERC20 xt, IGearingToken gt,,) = market.tokens();

        if (gt.ownerOf(gtId) != msg.sender) {
            revert GtNotOwnedBySender();
        }

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        market.issueFtByExistedGt(address(this), debtAmt, gtId);
        xt.safeTransferFrom(msg.sender, address(this), borrowAmt);
        if (isV1) {
            xt.safeIncreaseAllowance(address(market), borrowAmt);
            ft.safeIncreaseAllowance(address(market), borrowAmt);
        }
        market.burn(recipient, borrowAmt);

        emit Borrow(market, gtId, msg.sender, recipient, 0, debtAmt, borrowAmt.toUint128());
    }

    function flashRepayFromCollForV1(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        uint256 expectedOutput,
        SwapPath[] memory swapPaths
    ) external whenNotPaused noCallbackReentrant returns (uint256 netTokenOut) {
        (,, IGearingToken gtToken,, IERC20 debtToken) = market.tokens();
        assembly {
            tstore(T_CALLBACK_ADDRESS_STORE, gtToken) // set callback address
        }
        gtToken.safeTransferFrom(msg.sender, address(this), gtId, "");
        bytes memory callbackData = abi.encode(swapPaths);
        callbackData = abi.encode(FlashRepayOptions.REPAY, callbackData);
        gtToken.flashRepay(gtId, byDebtToken, callbackData);
        netTokenOut = debtToken.balanceOf(address(this));
        if (netTokenOut < expectedOutput) {
            revert InsufficientTokenOut(address(debtToken), expectedOutput, netTokenOut);
        }
        debtToken.safeTransfer(recipient, netTokenOut);
    }

    function flashRepayFromCollForV2(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        bool byDebtToken,
        uint256 expectedOutput,
        uint256 removedCollateral,
        SwapPath[] memory swapPaths
    ) external whenNotPaused noCallbackReentrant returns (uint256 netTokenOut) {
        (,, IGearingToken gtToken,, IERC20 debtToken) = market.tokens();
        assembly {
            tstore(T_CALLBACK_ADDRESS_STORE, gtToken) // set callback address
        }
        gtToken.safeTransferFrom(msg.sender, address(this), gtId, "");
        bytes memory callbackData = abi.encode(swapPaths);
        callbackData = abi.encode(FlashRepayOptions.REPAY, callbackData);
        bool repayAll = IGearingTokenV2(address(gtToken)).flashRepay(
            gtId, repayAmt, byDebtToken, abi.encode(removedCollateral), callbackData
        );
        if (!repayAll) {
            gtToken.safeTransferFrom(address(this), msg.sender, gtId);
        }
        netTokenOut = debtToken.balanceOf(address(this));
        if (netTokenOut < expectedOutput) {
            revert InsufficientTokenOut(address(debtToken), expectedOutput, netTokenOut);
        }
        debtToken.safeTransfer(recipient, netTokenOut);
    }

    function rolloverGtForV1(
        IGearingToken gtToken,
        uint256 gtId,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) external whenNotPaused noCallbackReentrant returns (uint256 newGtId) {
        return _rolloverGt(true, gtToken, gtId, 0, 0, additionalAsset, additionalAmt, rolloverData);
    }

    function rolloverGtForV2(
        IGearingToken gtToken,
        uint256 gtId,
        uint256 repayAmt,
        uint256 removedCollateral,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) external whenNotPaused noCallbackReentrant returns (uint256 newGtId) {
        return
            _rolloverGt(false, gtToken, gtId, repayAmt, removedCollateral, additionalAsset, additionalAmt, rolloverData);
    }

    function _rolloverGt(
        bool isV1,
        IGearingToken gtToken,
        uint256 gtId,
        uint256 repayAmt,
        uint256 removedCollateral,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) internal returns (uint256 newGtId) {
        assembly {
            // set callback address
            tstore(T_CALLBACK_ADDRESS_STORE, gtToken)
            // clear ts stograge
            tstore(T_ROLLOVER_GT_RESERVE_STORE, 0)
        }
        // additional debt/new collateral token to reduce the ltv
        if (additionalAmt != 0) {
            additionalAsset.safeTransferFrom(msg.sender, address(this), additionalAmt);
        }
        gtToken.safeTransferFrom(msg.sender, address(this), gtId, "");
        if (isV1) {
            gtToken.flashRepay(gtId, true, rolloverData);
        } else if (
            !IGearingTokenV2(address(gtToken)).flashRepay(
                gtId, repayAmt.toUint128(), true, abi.encode(removedCollateral), rolloverData
            )
        ) {
            // if the flash repay is not all repaid, we need to transfer the gt back to the sender
            gtToken.safeTransferFrom(address(this), msg.sender, gtId);
        }
        assembly {
            newGtId := tload(T_ROLLOVER_GT_RESERVE_STORE)
        }
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function swapAndRepay(IGearingToken gt, uint256 gtId, uint128 repayAmt, bool byDebtToken, SwapPath[] memory paths)
        external
        override
        whenNotPaused
        checkSwapPaths(paths)
        returns (uint256[] memory netOutOrIns)
    {
        netOutOrIns = _executeSwapPaths(paths);
        IERC20 repayToken = IERC20(paths[0].units[paths[0].units.length - 1].tokenOut);
        repayToken.safeIncreaseAllowance(address(gt), repayAmt);
        gt.repay(gtId, repayAmt, byDebtToken);
    }

    /// @dev Market flash leverage flashloan callback
    function executeOperation(address, IERC20, uint256, bytes memory data)
        external
        override
        onlyCallbackAddress
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
        collateralData = abi.encode(collateralBalance);
    }

    /// @dev Gt flash repay flashloan callback
    function executeOperation(
        IERC20 repayToken,
        uint128 repayAmt,
        address,
        bytes memory removedCollateralData,
        bytes memory callbackData
    ) external override onlyCallbackAddress {
        (FlashRepayOptions option, bytes memory data) = abi.decode(callbackData, (FlashRepayOptions, bytes));
        if (option == FlashRepayOptions.REPAY) {
            _flashRepay(data);
        } else if (option == FlashRepayOptions.ROLLOVER) {
            _rollover(repayToken, repayAmt, removedCollateralData, data);
        } else if (option == FlashRepayOptions.ROLLOVER_AAVE) {
            _rolloverToAave(repayToken, repayAmt, removedCollateralData, data);
        } else if (option == FlashRepayOptions.ROLLOVER_MORPHO) {
            _rolloverToMorpho(repayToken, repayAmt, removedCollateralData, data);
        }
        repayToken.safeIncreaseAllowance(msg.sender, repayAmt);
    }

    function _flashRepay(bytes memory callbackData) internal {
        SwapPath[] memory swapPaths = abi.decode(callbackData, (SwapPath[]));
        _executeSwapPaths(swapPaths);
    }

    function _rollover(IERC20 debtToken, uint256 repayAmt, bytes memory collateralData, bytes memory callbackData)
        internal
    {
        (
            address recipient,
            ITermMaxMarket market,
            uint128 maxLtv,
            SwapPath memory collateralPath,
            SwapPath memory debtTokenPath
        ) = abi.decode(callbackData, (address, ITermMaxMarket, uint128, SwapPath, SwapPath));

        // do swap to get the new collateral
        uint256 newCollateralAmt = collateralPath.units.length == 0
            ? 0
            : _executeSwapUnits(address(this), abi.decode(collateralData, (uint256)), collateralPath.units);
        collateralData = abi.encode(newCollateralAmt);

        (IERC20 ft,, IGearingToken gt, address collateral,) = market.tokens();
        uint256 gtId;
        {
            // issue new gt
            uint256 mintGtFeeRatio = market.mintGtFeeRatio();
            uint128 newDebtAmt = (
                (debtTokenPath.inputAmount * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)
            ).toUint128();
            IERC20(collateral).safeIncreaseAllowance(address(gt), newCollateralAmt);
            (gtId,) = market.issueFt(address(this), newDebtAmt, collateralData);
        }
        {
            uint256 netFtCost = _executeSwapUnits(address(this), debtTokenPath.inputAmount, debtTokenPath.units);
            // check remaining ft amount
            if (debtTokenPath.inputAmount > netFtCost) {
                uint256 repaidFtAmt = debtTokenPath.inputAmount - netFtCost;
                ft.safeIncreaseAllowance(address(gt), repaidFtAmt);
                // repay in ft, bool false means not using debt token
                gt.repay(gtId, repaidFtAmt.toUint128(), false);
            }
            // check remaining debt token amount
            uint256 totalDebtTokenAmt = debtToken.balanceOf(address(this));
            if (totalDebtTokenAmt > repayAmt) {
                uint256 repaidDebtAmt = totalDebtTokenAmt - repayAmt;
                debtToken.safeIncreaseAllowance(address(gt), repaidDebtAmt);
                // repay in debt token, bool true means using debt token
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

    function _rolloverToAave(IERC20 debtToken, uint256 repayAmt, bytes memory, bytes memory callbackData) internal {
        (
            address recipient,
            IERC20 collateral,
            IAaveV3PoolMinimal aave,
            uint256 interestRateMode,
            uint16 referralCode,
            SwapPath memory collateralPath
        ) = abi.decode(callbackData, (address, IERC20, IAaveV3PoolMinimal, uint256, uint16, SwapPath));
        if (collateralPath.units.length > 0) {
            // do swap to get the new collateral
            uint256 newCollateralAmt = _doSwap(collateral.balanceOf(address(this)), collateralPath.units);
            IERC20 newCollateral = IERC20(collateralPath.units[collateralPath.units.length - 1].tokenOut);
            newCollateral.safeIncreaseAllowance(address(aave), newCollateralAmt);
            aave.deposit(address(newCollateral), newCollateralAmt, recipient, referralCode);
        } else {
            uint256 collateralAmt = collateral.balanceOf(address(this));
            collateral.safeIncreaseAllowance(address(aave), collateralAmt);
            aave.deposit(address(collateral), collateralAmt, recipient, referralCode);
        }
        repayAmt = repayAmt - debtToken.balanceOf(address(this));
        aave.borrow(address(debtToken), repayAmt, interestRateMode, referralCode, recipient);
    }

    function _rolloverToMorpho(IERC20 debtToken, uint256 repayAmt, bytes memory, bytes memory callbackData) internal {
        (address recipient, IERC20 collateral, IMorpho morpho, Id marketId, SwapPath memory collateralPath) =
            abi.decode(callbackData, (address, IERC20, IMorpho, Id, SwapPath));
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        if (collateralPath.units.length > 0) {
            // do swap to get the new collateral
            uint256 newCollateralAmt = _doSwap(collateral.balanceOf(address(this)), collateralPath.units);
            IERC20 newCollateral = IERC20(collateralPath.units[collateralPath.units.length - 1].tokenOut);
            newCollateral.safeIncreaseAllowance(address(morpho), newCollateralAmt);
            morpho.supplyCollateral(marketParams, newCollateralAmt, recipient, "");
        } else {
            uint256 collateralAmt = collateral.balanceOf(address(this));
            collateral.safeIncreaseAllowance(address(morpho), collateralAmt);
            morpho.supplyCollateral(marketParams, collateralAmt, recipient, "");
        }
        repayAmt = repayAmt - debtToken.balanceOf(address(this));
        /// @dev Borrow the repay amount from morpho, share amount is 0 and receiver is the router itself
        morpho.borrow(marketParams, repayAmt, 0, recipient, address(this));
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
