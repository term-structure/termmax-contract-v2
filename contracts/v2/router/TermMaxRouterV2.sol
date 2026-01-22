// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
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
import {ITermMaxRouterV2, SwapPath, FlashLoanType, FlashRepayOptions} from "./ITermMaxRouterV2.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {IGearingTokenV2} from "../tokens/IGearingTokenV2.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {IERC20SwapAdapter} from "./IERC20SwapAdapter.sol";
import {IAaveV3Pool} from "../extensions/aave/IAaveV3Pool.sol";
import {ICreditDelegationToken} from "../extensions/aave/ICreditDelegationToken.sol";
import {IMorpho, Id, MarketParams, Authorization, Signature} from "../extensions/morpho/IMorpho.sol";
import {RouterErrorsV2} from "../errors/RouterErrorsV2.sol";
import {RouterEventsV2} from "../events/RouterEventsV2.sol";
import {ArrayUtilsV2} from "../lib/ArrayUtilsV2.sol";
import {IWhitelistManager} from "../access/IWhitelistManager.sol";
import {VersionV2} from "../VersionV2.sol";

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
    VersionV2,
    ReentrancyGuardUpgradeable
{
    using SafeCast for *;
    using TransferUtilsV2 for IERC20;
    using Math for *;
    using ArrayUtilsV2 for *;

    /// @notice whitelist mapping of adapter
    mapping(address => bool) public adapterWhitelist;
    IWhitelistManager internal whitelistManager;

    uint256 private constant T_ROLLOVER_GT_RESERVE_STORE = 0;
    uint256 private constant T_CALLBACK_ADDRESS_STORE = 1;
    uint256 private constant T_CALLER = 2;

    modifier onlyCallbackAddress() {
        address callbackAddress;
        assembly {
            callbackAddress := tload(T_CALLBACK_ADDRESS_STORE)
            // clear callback address after use
            tstore(T_CALLBACK_ADDRESS_STORE, 0)
        }
        if (_msgSender() != callbackAddress) {
            revert RouterErrorsV2.CallbackAddressNotMatch();
        }
        _;
    }

    modifier checkSwapPaths(SwapPath[] memory paths) {
        if (paths.length == 0 || paths[0].units.length == 0) revert RouterErrorsV2.SwapPathsIsEmpty();
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin, address whitelistManager_) external initializer {
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();
        __Ownable_init_unchained(admin);
        _setWhitelistManager(whitelistManager_);
    }

    function initializeV2(address whitelistManager_) external reinitializer(2) {
        __ReentrancyGuard_init_unchained();
        _setWhitelistManager(whitelistManager_);
    }

    function setWhitelistManager(address whitelistManager_) external onlyOwner {
        _setWhitelistManager(whitelistManager_);
    }

    function _setWhitelistManager(address whitelistManager_) internal {
        whitelistManager = IWhitelistManager(whitelistManager_);
        emit RouterEventsV2.WhitelistManagerUpdated(whitelistManager_);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function swapTokens(SwapPath[] memory paths)
        external
        nonReentrant
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
                uint256 balanceOnChain = IERC20(path.units[0].tokenIn).balanceOf(address(this));
                netTokenOuts[i] = _executeSwapUnits(path.recipient, balanceOnChain, path.units);
            } else {
                IERC20(path.units[0].tokenIn).safeTransferFrom(_msgSender(), address(this), path.inputAmount);
                netTokenOuts[i] = _executeSwapUnits(path.recipient, path.inputAmount, path.units);
            }
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
            _checkAdapterWhitelist(units[i].adapter);
            bytes memory dataToSwap = i == units.length - 1
                ? abi.encodeCall(
                    IERC20SwapAdapter.swap, (recipient, units[i].tokenIn, units[i].tokenOut, inputAmt, units[i].swapData)
                )
                : abi.encodeCall(
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

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function leverage(
        address recipient,
        ITermMaxMarket market,
        uint128 maxLtv,
        bool isV1,
        SwapPath[] memory inputPaths,
        SwapPath memory swapXtPath,
        SwapPath memory swapCollateralPath
    ) external nonReentrant whenNotPaused returns (uint256 gtId, uint256 netXtOut) {
        assembly {
            tstore(T_CALLBACK_ADDRESS_STORE, market) // set callback address
        }
        (, IERC20 xt, IGearingToken gt,, IERC20 debtToken) = market.tokens();
        // transfer input tokens(may swap any token to debt token)
        _executeSwapPaths(inputPaths);
        uint256 totalDebtToken = debtToken.balanceOf(address(this));
        // swap debt token to xt token if needed
        if (swapXtPath.units.length != 0) {
            netXtOut = _executeSwapUnits(address(this), swapXtPath.inputAmount, swapXtPath.units);
        }
        uint256 totalXt = xt.balanceOf(address(this));
        bytes memory callbackData = abi.encode(address(gt), swapCollateralPath.units);
        if (isV1) {
            xt.safeIncreaseAllowance(address(market), totalXt);
            gtId = market.leverageByXt(recipient, totalXt.toUint128(), callbackData);
        } else {
            gtId = ITermMaxMarketV2(address(market)).leverageByXt(
                address(this), recipient, totalXt.toUint128(), callbackData
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
            _msgSender(),
            recipient,
            (totalDebtToken).toUint128(),
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
    ) external nonReentrant whenNotPaused returns (uint256) {
        (IERC20 ft,, IGearingToken gt, address collateralAddr,) = market.tokens();
        IERC20(collateralAddr).safeTransferFrom(_msgSender(), address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), maxDebtAmt, abi.encode(collInAmt));
        gt.safeTransferFrom(address(this), recipient, gtId);
        uint256 netTokenIn = _executeSwapUnits(swapFtPath.recipient, ftOutAmt, swapFtPath.units);
        uint256 repayAmt = ftOutAmt - netTokenIn;
        if (repayAmt > 0) {
            ft.safeIncreaseAllowance(address(gt), repayAmt);
            // repay in ft, bool false means not using debt token
            gt.repay(gtId, repayAmt.toUint128(), false);
        }
        emit Borrow(market, gtId, _msgSender(), recipient, collInAmt, ftOutAmt, netTokenIn.toUint128());
        return gtId;
    }

    function borrowTokenFromCollateralAndXt(
        address recipient,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 borrowAmt,
        bool isV1
    ) external nonReentrant whenNotPaused returns (uint256) {
        (IERC20 ft, IERC20 xt, IGearingToken gt, address collateralAddr,) = market.tokens();

        IERC20(collateralAddr).safeTransferFrom(_msgSender(), address(this), collInAmt);
        IERC20(collateralAddr).safeIncreaseAllowance(address(gt), collInAmt);

        uint256 mintGtFeeRatio = market.mintGtFeeRatio();
        uint128 debtAmt = ((borrowAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)).toUint128();

        (uint256 gtId, uint128 ftOutAmt) = market.issueFt(address(this), debtAmt, abi.encode(collInAmt));
        gt.safeTransferFrom(address(this), recipient, gtId);
        borrowAmt = borrowAmt.min(ftOutAmt);
        xt.safeTransferFrom(_msgSender(), address(this), borrowAmt);
        if (isV1) {
            xt.safeIncreaseAllowance(address(market), borrowAmt);
            ft.safeIncreaseAllowance(address(market), borrowAmt);
        }

        market.burn(recipient, borrowAmt);

        emit Borrow(market, gtId, _msgSender(), recipient, collInAmt, debtAmt, borrowAmt.toUint128());
        return gtId;
    }

    function flashRepayFromColl(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        uint256 expectedOutput,
        bytes memory callbackData
    ) external nonReentrant whenNotPaused returns (uint256 netTokenOut) {
        return _flashRepayFromCollateral(recipient, market, gtId, byDebtToken, expectedOutput, callbackData, false);
    }

    function _flashRepayFromCollateral(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        bool byDebtToken,
        uint256 expectedOutput,
        bytes memory callbackData,
        bool collateralIsOutput
    ) internal returns (uint256 netTokenOut) {
        (,, IGearingToken gtToken, address collateral, IERC20 debtToken) = market.tokens();
        assembly {
            // set callback address
            tstore(T_CALLBACK_ADDRESS_STORE, gtToken)
        }
        gtToken.safeTransferFrom(_msgSender(), address(this), gtId, "");
        gtToken.flashRepay(gtId, byDebtToken, callbackData);
        IERC20 outputToken = collateralIsOutput ? IERC20(collateral) : debtToken;
        netTokenOut = outputToken.balanceOf(address(this));
        if (netTokenOut < expectedOutput) {
            revert InsufficientTokenOut(address(outputToken), expectedOutput, netTokenOut);
        }
        outputToken.safeTransfer(recipient, netTokenOut);
        // check if there is any remaining token in the router if collateral is output token
        if (collateralIsOutput) {
            uint256 remainingDebtToken = debtToken.balanceOf(address(this));
            if (remainingDebtToken != 0) {
                debtToken.safeTransfer(recipient, remainingDebtToken);
            }
        }
        emit RouterEventsV2.FlashRepay(address(gtToken), gtId, netTokenOut);
    }

    function flashRepayToGetCollateral(
        address recipient,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 expectedOutput,
        bytes memory callbackData
    ) external nonReentrant whenNotPaused returns (uint256 netTokenOut) {
        /// @dev flashRepayToGetCollateral always repays by debt token
        bool byDebtToken = true;
        return _flashRepayFromCollateral(recipient, market, gtId, byDebtToken, expectedOutput, callbackData, true);
    }

    function rolloverGt(
        IGearingToken gtToken,
        uint256 gtId,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) external nonReentrant whenNotPaused returns (uint256 newGtId) {
        return _rolloverGt(gtToken, gtId, additionalAsset, additionalAmt, rolloverData);
    }

    function _rolloverGt(
        IGearingToken gtToken,
        uint256 gtId,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        bytes memory rolloverData
    ) internal returns (uint256 newGtId) {
        address firstCaller = _msgSender();
        assembly {
            // set callback address
            tstore(T_CALLBACK_ADDRESS_STORE, gtToken)
            // clear ts stograge
            tstore(T_ROLLOVER_GT_RESERVE_STORE, 0)
            // set caller address
            tstore(T_CALLER, firstCaller)
        }
        // additional debt/new collateral token to reduce the ltv
        if (additionalAmt != 0) {
            additionalAsset.safeTransferFrom(firstCaller, address(this), additionalAmt);
        }
        gtToken.safeTransferFrom(firstCaller, address(this), gtId, "");
        gtToken.flashRepay(gtId, true, rolloverData);
        assembly {
            newGtId := tload(T_ROLLOVER_GT_RESERVE_STORE)
        }
        emit RouterEventsV2.RolloverGt(address(gtToken), gtId, newGtId, address(additionalAsset), additionalAmt);
    }

    /**
     * @inheritdoc ITermMaxRouterV2
     */
    function swapAndRepay(IGearingToken gt, uint256 gtId, uint128 repayAmt, bool byDebtToken, SwapPath[] memory paths)
        external
        override
        nonReentrant
        whenNotPaused
        checkSwapPaths(paths)
        returns (uint256[] memory netOutOrIns)
    {
        netOutOrIns = _executeSwapPaths(paths);
        IERC20 repayToken = IERC20(paths[0].units[paths[0].units.length - 1].tokenOut);
        repayToken.safeIncreaseAllowance(address(gt), repayAmt);
        gt.repay(gtId, repayAmt, byDebtToken);
        uint256 remainingRepayToken = repayToken.balanceOf(address(this));
        if (remainingRepayToken != 0) {
            repayToken.safeTransfer(_msgSender(), remainingRepayToken);
        }
        emit RouterEventsV2.SwapAndRepay(address(gt), gtId, repayAmt, remainingRepayToken);
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
        uint256 collateralBalance = _executeSwapUnits(address(this), totalAmount, units);
        SwapUnit memory lastUnit = units[units.length - 1];
        _checkAdapterWhitelist(lastUnit.adapter);
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
        } else {
            address firstCaller;
            assembly {
                firstCaller := tload(T_CALLER)
                //clear caller address after use
                tstore(T_CALLER, 0)
            }
            if (option == FlashRepayOptions.ROLLOVER) {
                _rollover(repayToken, repayAmt, removedCollateralData, data);
            } else if (option == FlashRepayOptions.ROLLOVER_AAVE) {
                _rolloverToAave(firstCaller, repayToken, repayAmt, removedCollateralData, data);
            } else if (option == FlashRepayOptions.ROLLOVER_MORPHO) {
                _rolloverToMorpho(firstCaller, repayToken, repayAmt, removedCollateralData, data);
            }
        }
        repayToken.safeIncreaseAllowance(_msgSender(), repayAmt);
    }

    function _flashRepay(bytes memory callbackData) internal {
        // By debt token: collateral-> debt token
        // By ft token: collateral-> debt token -> exact ft token
        SwapPath memory repayTokenPath = abi.decode(callbackData, (SwapPath));
        _executeSwapUnits(address(this), repayTokenPath.inputAmount, repayTokenPath.units);
    }

    function _rollover(IERC20, uint256, bytes memory, bytes memory callbackData) internal {
        (
            address recipient,
            ITermMaxMarket market,
            uint128 maxLtv,
            SwapPath memory collateralPath,
            SwapPath memory debtTokenPath
        ) = abi.decode(callbackData, (address, ITermMaxMarket, uint128, SwapPath, SwapPath));

        // Do swap to get the new collateral,(the inpput amount may contains additional old collateral)
        if (collateralPath.units.length != 0) {
            _executeSwapUnits(address(this), collateralPath.inputAmount, collateralPath.units);
        }

        (IERC20 ft,, IGearingToken gt, address collateral,) = market.tokens();
        // Get balances, may contain additional new collateral
        uint256 newCollateralAmt = IERC20(collateral).balanceOf(address(this));
        uint256 gtId;
        // issue new gt to get new ft token
        {
            // issue new gt
            uint256 mintGtFeeRatio = market.mintGtFeeRatio();
            uint128 newDebtAmt = (
                (debtTokenPath.inputAmount * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio)
            ).toUint128();
            IERC20(collateral).safeIncreaseAllowance(address(gt), newCollateralAmt);
            (gtId,) = market.issueFt(address(this), newDebtAmt, abi.encode(newCollateralAmt));
            // transfer new gt to recipient
            gt.safeTransferFrom(address(this), recipient, gtId);
        }
        // Swap ft to debt token to repay(swap amount + additional debt token amount should equal repay amt)
        {
            uint256 netFtCost = _executeSwapUnits(address(this), debtTokenPath.inputAmount, debtTokenPath.units);
            // check remaining ft amount
            if (debtTokenPath.inputAmount > netFtCost) {
                uint256 repaidFtAmt = debtTokenPath.inputAmount - netFtCost;
                ft.safeIncreaseAllowance(address(gt), repaidFtAmt);
                // repay in ft, bool false means not using debt token
                gt.repay(gtId, repaidFtAmt.toUint128(), false);
            }
            (, uint128 ltv,) = gt.getLiquidationInfo(gtId);
            if (ltv > maxLtv) {
                revert LtvBiggerThanExpected(maxLtv, ltv);
            }
        }
        assembly {
            tstore(T_ROLLOVER_GT_RESERVE_STORE, gtId)
        }
    }

    function _rolloverToAave(
        address caller,
        IERC20 debtToken,
        uint256 repayAmt,
        bytes memory,
        bytes memory callbackData
    ) internal {
        (
            IERC20 collateral,
            IAaveV3Pool aave,
            uint256 interestRateMode,
            uint16 referralCode,
            ICreditDelegationToken.AaveDelegationParams memory delegationParams,
            SwapPath memory collateralPath
        ) = abi.decode(
            callbackData, (IERC20, IAaveV3Pool, uint256, uint16, ICreditDelegationToken.AaveDelegationParams, SwapPath)
        );
        if (delegationParams.delegator != address(0)) {
            // delegate with sig
            delegationParams.aaveDebtToken.delegationWithSig(
                delegationParams.delegator,
                delegationParams.delegatee,
                delegationParams.value,
                delegationParams.deadline,
                delegationParams.v,
                delegationParams.r,
                delegationParams.s
            );
        }
        repayAmt = repayAmt - debtToken.balanceOf(address(this));
        if (collateralPath.units.length > 0) {
            // do swap to get the new collateral
            uint256 newCollateralAmt =
                _executeSwapUnits(address(this), collateral.balanceOf(address(this)), collateralPath.units);
            IERC20 newCollateral = IERC20(collateralPath.units[collateralPath.units.length - 1].tokenOut);
            newCollateral.safeIncreaseAllowance(address(aave), newCollateralAmt);
            aave.supply(address(newCollateral), newCollateralAmt, caller, referralCode);
        } else {
            uint256 collateralAmt = collateral.balanceOf(address(this));
            collateral.safeIncreaseAllowance(address(aave), collateralAmt);
            aave.supply(address(collateral), collateralAmt, caller, referralCode);
        }
        aave.borrow(address(debtToken), repayAmt, interestRateMode, referralCode, caller);
    }

    function _rolloverToMorpho(
        address caller,
        IERC20 debtToken,
        uint256 repayAmt,
        bytes memory,
        bytes memory callbackData
    ) internal {
        (
            IERC20 collateral,
            IMorpho morpho,
            Id marketId,
            Authorization memory auth,
            Signature memory sig,
            SwapPath memory collateralPath
        ) = abi.decode(callbackData, (IERC20, IMorpho, Id, Authorization, Signature, SwapPath));
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        if (auth.authorized != address(0)) {
            // auth with sig
            morpho.setAuthorizationWithSig(auth, sig);
        }
        repayAmt = repayAmt - debtToken.balanceOf(address(this));
        if (collateralPath.units.length > 0) {
            // do swap to get the new collateral
            uint256 newCollateralAmt =
                _executeSwapUnits(address(this), collateral.balanceOf(address(this)), collateralPath.units);
            IERC20 newCollateral = IERC20(collateralPath.units[collateralPath.units.length - 1].tokenOut);
            newCollateral.safeIncreaseAllowance(address(morpho), newCollateralAmt);
            morpho.supplyCollateral(marketParams, newCollateralAmt, caller, "");
        } else {
            uint256 collateralAmt = collateral.balanceOf(address(this));
            collateral.safeIncreaseAllowance(address(morpho), collateralAmt);
            morpho.supplyCollateral(marketParams, collateralAmt, caller, "");
        }
        /// @dev Borrow the repay amount from morpho, share amount is 0 and receiver is the router itself
        morpho.borrow(marketParams, repayAmt, 0, caller, address(this));
    }

    function _checkAdapterWhitelist(address adapter) internal view {
        if (!whitelistManager.isWhitelisted(adapter, IWhitelistManager.ContractModule.ADAPTER)) {
            revert AdapterNotWhitelisted(adapter);
        }
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
