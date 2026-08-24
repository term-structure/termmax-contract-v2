// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {IGearingTokenV2} from "../tokens/IGearingTokenV2.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxRouterV2, SwapPath} from "./ITermMaxRouterV2.sol";
import {ITermMaxRouterV2_02, FlashLoanProvider} from "./ITermMaxRouterV2_02.sol";
import {ITermMaxVaultV2} from "../vault/ITermMaxVaultV2.sol";
import {IMorpho, Id, MarketParams, Authorization, Signature} from "../extensions/morpho/IMorpho.sol";
import {IAaveV3Pool} from "../extensions/aave/IAaveV3Pool.sol";
import {RouterErrors} from "../../v1/errors/RouterErrors.sol";
import {RouterErrorsV2} from "../errors/RouterErrorsV2.sol";
import {RouterEventsV2} from "../events/RouterEventsV2.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {WithWhitelistCheck, IWhitelistManager} from "../access/WithWhitelistCheck.sol";
import {VersionV2_0_2} from "../VersionV2_0_2.sol";

/// @dev Which flow a flash loan callback belongs to, packed as the head of its payload
enum FlashCallbackKind {
    ROLLOVER_GT,
    ROLLOVER_FROM_LENDING
}

/**
 * @title TermMax Router V2_02
 * @author Term Structure Labs
 * @notice Extension of TermMaxRouterV2, deployed as a standalone contract because the
 *         main router is close to the EIP-170 bytecode limit. New router features land
 *         here, composing the existing TermMaxRouterV2 functions where possible — this
 *         contract only orchestrates and holds no swap or whitelist logic of its own.
 *         Current features:
 *         - flashRolloverGt: roll a GT position (fully or partially) into a new market,
 *           using an external flash loan (Morpho / Aave) as temporary vault liquidity
 *         - rolloverFromLendingProtocol: roll an Aave / Morpho borrow position (fully or
 *           partially) into a TermMax fixed rate position, using a flash loan from that same
 *           protocol
 */
contract TermMaxRouterV2_02 is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721Receiver,
    ITermMaxRouterV2_02,
    VersionV2_0_2,
    WithWhitelistCheck
{
    using TransferUtilsV2 for IERC20;
    using SafeCast for uint256;

    uint256 private constant T_NEW_GT_STORE = 0;
    uint256 private constant T_CALLBACK_ADDRESS_STORE = 1;
    /// @dev The account that opened the flow. It is NEVER read back from the flash loan
    /// payload, so a flash lender can not name someone else as the position to act on.
    uint256 private constant T_CALLER_STORE = 2;

    /// @dev Aave V3 stable rate borrowing is deprecated, only variable rate debt is rolled over
    uint256 private constant AAVE_VARIABLE_RATE_MODE = 2;
    /// @dev Morpho SharesMathLib constants, used to convert the flash loan into borrow shares
    uint256 private constant MORPHO_VIRTUAL_SHARES = 1e6;
    uint256 private constant MORPHO_VIRTUAL_ASSETS = 1;

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

    constructor(address _whitelistManager)
        WithWhitelistCheck(_whitelistManager, IWhitelistManager.ContractModule.MARKET)
    {}

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address admin) external initializer {
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();
        __Ownable_init_unchained(admin);
    }

    /**
     * @inheritdoc ITermMaxRouterV2_02
     */
    function flashRolloverGt(
        ITermMaxMarket market,
        uint256 gtId,
        uint128 repayAmt,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        FlashLoanProvider provider,
        address flashLender,
        ITermMaxVaultV2 vault,
        address[] memory ftOrders,
        uint256[] memory ftAmounts,
        bytes memory rolloverData
    ) external nonReentrant whenNotPaused onlyWhitelisted(address(market)) returns (uint256 newGtId) {
        (,, IGearingToken gtToken, address collateral, IERC20 debtToken) = market.tokens();
        address firstCaller = _msgSender();
        if (ftOrders.length != ftAmounts.length) revert RouterErrors.OrdersAndAmtsLengthNotMatch();
        if (additionalAmt != 0 && address(additionalAsset) != address(debtToken) && address(additionalAsset) != collateral)
        {
            revert RouterErrorsV2.InvalidAdditionalAsset();
        }
        assembly {
            // the flash lender is the only address allowed to call back
            tstore(T_CALLBACK_ADDRESS_STORE, flashLender)
            // the flow acts for this account only
            tstore(T_CALLER_STORE, firstCaller)
            // clear ts stograge
            tstore(T_NEW_GT_STORE, 0)
        }
        // Optional debt token to cover rollover cost, or collateral to strengthen the new position.
        if (additionalAmt != 0) {
            additionalAsset.safeTransferFrom(firstCaller, address(this), additionalAmt);
        }
        // pull the gt to act as its owner, it is returned to the caller at the end
        gtToken.safeTransferFrom(firstCaller, address(this), gtId, "");
        {
            (, uint128 debtAmt,) = gtToken.loanInfo(gtId);
            if (repayAmt > debtAmt) {
                repayAmt = debtAmt;
            }
        }
        uint256 totalFtAmount;
        uint256 sharesToMint;
        for (uint256 i = 0; i < ftAmounts.length; ++i) {
            totalFtAmount += ftAmounts[i];
            // Each withdrawFts call rounds its share burn independently, so the required
            // shares must be calculated per order rather than from the aggregate FT amount.
            sharesToMint += IERC4626(address(vault)).previewWithdraw(ftAmounts[i]);
        }
        if (totalFtAmount != repayAmt) revert RouterErrorsV2.InvalidFtAmount(repayAmt, totalFtAmount);
        // the exact assets required to mint just enough shares to redeem `repayAmt` of ft
        uint256 flashLoanAmt = IERC4626(address(vault)).previewMint(sharesToMint);
        bytes memory data = abi.encode(
            FlashCallbackKind.ROLLOVER_GT,
            abi.encode(market, gtId, repayAmt, sharesToMint, vault, ftOrders, ftAmounts, rolloverData)
        );
        if (provider == FlashLoanProvider.MORPHO) {
            IMorpho(flashLender).flashLoan(address(debtToken), flashLoanAmt, data);
        } else {
            IAaveV3Pool(flashLender).flashLoanSimple(address(this), address(debtToken), flashLoanAmt, data, 0);
        }
        assembly {
            newGtId := tload(T_NEW_GT_STORE)
        }
        // return the (partially repaid) old position to the caller
        gtToken.safeTransferFrom(address(this), firstCaller, gtId, "");
        /// @dev Redeem the rounding-dust shares(if any) to the caller as debt token.
        /// The vault reverts if that is not allowed within this transaction — the dust
        /// is wei-level so it is not worth further handling.
        uint256 remainingShares = IERC4626(address(vault)).balanceOf(address(this));
        if (remainingShares != 0) {
            IERC4626(address(vault)).redeem(remainingShares, firstCaller, address(this));
        }
        // refund the unconsumed collateral(if any) and debt token buffer
        uint256 remainingCollateral = IERC20(collateral).balanceOf(address(this));
        if (remainingCollateral != 0) {
            IERC20(collateral).safeTransfer(firstCaller, remainingCollateral);
        }
        uint256 remainingDebtToken = debtToken.balanceOf(address(this));
        if (remainingDebtToken != 0) {
            debtToken.safeTransfer(firstCaller, remainingDebtToken);
        }
        emit RouterEventsV2.FlashRolloverGt(address(gtToken), gtId, newGtId, flashLender, flashLoanAmt, additionalAmt);
    }

    /**
     * @inheritdoc ITermMaxRouterV2_02
     */
    function rolloverFromLendingProtocol(
        ITermMaxMarket newMarket,
        uint256 flashAmt,
        uint256 collateralAmt,
        IERC20 additionalAsset,
        uint256 additionalAmt,
        FlashLoanProvider protocol,
        address lendingPool,
        bytes memory positionData,
        bytes memory delegationData,
        bytes memory rolloverData
    ) external nonReentrant whenNotPaused onlyWhitelisted(address(newMarket)) returns (uint256 newGtId) {
        address positionOwner = _msgSender();
        /// @dev The only `tokens()` read of the flow: the market's tokens travel to the callback
        /// in the payload instead of being read again there.
        (,, IGearingToken newGt, address collateral, IERC20 debtToken) = newMarket.tokens();
        // Optional debt token to cover rollover cost, or collateral to strengthen the new position.
        _pullAdditionalAsset(additionalAsset, additionalAmt, positionOwner, collateral, address(debtToken));
        /// @dev The flash loan is sized by the caller: nothing about the third party position is
        /// read here, the callback unwinds it against whatever it actually holds. Any part of the
        /// loan the repayment does not need stays here and pays the loan back.
        _takeLendingFlashLoan(
            protocol,
            lendingPool,
            address(debtToken),
            flashAmt,
            positionOwner,
            _encodeLendingPayload(
                protocol,
                positionData,
                collateralAmt,
                newMarket,
                newGt,
                collateral,
                debtToken,
                delegationData,
                rolloverData
            )
        );
        assembly {
            newGtId := tload(T_NEW_GT_STORE)
        }
        /// @dev Gt ids start at one, so a zero here means the lender returned without ever calling
        /// back: reverting keeps the caller's optional buffer with the caller instead of leaving
        /// it in this contract, since nothing is refunded below.
        if (newGtId == 0) revert RouterErrorsV2.RolloverNotExecuted();
        /// @dev Nothing is refunded and no allowance is revoked here: every wei of collateral goes
        /// into the new position, what the flash loan repayment does not need went back into that
        /// position as a repayment, and the allowances were set to exactly what their spenders
        /// pulled, so this contract holds nothing once the loan settles.
        emit RouterEventsV2.RolloverFromLendingProtocol(
            positionOwner, lendingPool, newGtId, flashAmt, collateralAmt, additionalAmt
        );
    }

    /// @dev Morpho flash loan callback
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external onlyCallbackAddress {
        _dispatchFlashCallback(_msgSender(), assets, 0, data);
    }

    /// @dev Aave V3 flash loan callback
    function executeOperation(address, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        onlyCallbackAddress
        returns (bool)
    {
        if (initiator != address(this)) revert RouterErrorsV2.InvalidFlashLoanInitiator();
        _dispatchFlashCallback(_msgSender(), amount, premium, params);
        return true;
    }

    /// @dev Route a flash loan callback back to the flow that took the loan.
    /// @dev The account the flow acts for is taken from transient storage, never from the
    /// payload, so a flash lender calling back with a payload of its own can still only ever
    /// move the assets of the account that opened the flow — and the position it opens is
    /// handed to that same account.
    function _dispatchFlashCallback(address flashLender, uint256 flashLoanAmt, uint256 premium, bytes memory data)
        internal
    {
        address positionOwner;
        assembly {
            positionOwner := tload(T_CALLER_STORE)
            // single use, clear it before running the flow
            tstore(T_CALLER_STORE, 0)
        }
        (FlashCallbackKind kind, bytes memory payload) = abi.decode(data, (FlashCallbackKind, bytes));
        if (kind == FlashCallbackKind.ROLLOVER_FROM_LENDING) {
            _rolloverFromLending(flashLender, positionOwner, flashLoanAmt, premium, payload);
        } else {
            _flashRollover(flashLender, positionOwner, flashLoanAmt, premium, payload);
        }
    }

    function _flashRollover(
        address flashLender,
        address firstCaller,
        uint256 flashLoanAmt,
        uint256 premium,
        bytes memory data
    ) internal {
        (
            ITermMaxMarket market,
            uint256 gtId,
            uint128 repayAmt,
            uint256 sharesToMint,
            ITermMaxVaultV2 vault,
            address[] memory ftOrders,
            uint256[] memory ftAmounts,
            bytes memory rolloverData
        ) = abi.decode(data, (ITermMaxMarket, uint256, uint128, uint256, ITermMaxVaultV2, address[], uint256[], bytes));
        (
            address routerV2,
            uint256 removedCollateral,
            ITermMaxMarket newMarket,
            uint128 maxDebtAmt,
            SwapPath memory swapFtPath
        ) = abi.decode(rolloverData, (address, uint256, ITermMaxMarket, uint128, SwapPath));

        (IERC20 ft,, IGearingToken gt, address collateral, IERC20 debtToken) = market.tokens();
        {
            // mint the exact shares needed to redeem `repayAmt` of the old market's ft
            debtToken.safeIncreaseAllowance(address(vault), flashLoanAmt);
            IERC4626(address(vault)).mint(sharesToMint, address(this));
            // burn the shares to redeem the old market's ft from the vault orders
            for (uint256 i = 0; i < ftOrders.length; i++) {
                vault.withdrawFts(ftOrders[i], ftAmounts[i], address(this), address(this));
            }
            // repay(maybe partially) the old gt in ft and move the freed collateral here,
            // the gt is not burned and the leftover position stays healthy(checked by the gt)
            ft.safeIncreaseAllowance(address(gt), repayAmt);
            // repay in ft, bool false means not using debt token
            IGearingTokenV2(address(gt))
                .repayAndRemoveCollateral(gtId, repayAmt, false, address(this), abi.encode(removedCollateral));
        }
        /// @dev Delegate issuing and selling the new ft to router v2. The collateral input
        /// is exactly the removed collateral and the new gt recipient is enforced to this
        /// contract, so neither can be hijacked by malicious parameters. The backend must
        /// set the sell path recipient to this contract so the sale proceeds come back
        /// here to repay the flash loan.
        uint256 newCollateralAmt = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeIncreaseAllowance(routerV2, newCollateralAmt);
        uint256 newGtId = ITermMaxRouterV2(routerV2).borrowTokenFromCollateral(
            address(this), newMarket, newCollateralAmt, maxDebtAmt, swapFtPath
        );
        // forward the new gt to the caller
        (,, IGearingToken newGt,,) = newMarket.tokens();
        newGt.safeTransferFrom(address(this), firstCaller, newGtId, "");
        assembly {
            tstore(T_NEW_GT_STORE, newGtId)
        }
        // approve the lender to pull the flash loan repayment
        debtToken.safeIncreaseAllowance(flashLender, flashLoanAmt + premium);
    }

    function _pullAdditionalAsset(
        IERC20 additionalAsset,
        uint256 additionalAmt,
        address positionOwner,
        address collateral,
        address debtToken
    ) internal {
        if (additionalAmt == 0) return;
        if (address(additionalAsset) != debtToken && address(additionalAsset) != collateral) {
            revert RouterErrorsV2.InvalidAdditionalAsset();
        }
        additionalAsset.safeTransferFrom(positionOwner, address(this), additionalAmt);
    }

    /// @dev The lending pool is also the flash lender: the debt token is borrowed from the very
    /// protocol whose debt it repays, so there is no third address to trust here.
    function _takeLendingFlashLoan(
        FlashLoanProvider protocol,
        address lendingPool,
        address debtToken,
        uint256 flashAmt,
        address positionOwner,
        bytes memory data
    ) internal {
        assembly {
            // the flash lender is the only address allowed to call back
            tstore(T_CALLBACK_ADDRESS_STORE, lendingPool)
            // the flow acts for this account only
            tstore(T_CALLER_STORE, positionOwner)
            // clear ts stograge
            tstore(T_NEW_GT_STORE, 0)
        }
        if (protocol == FlashLoanProvider.AAVE) {
            IAaveV3Pool(lendingPool).flashLoanSimple(address(this), debtToken, flashAmt, data, 0);
        } else {
            IMorpho(lendingPool).flashLoan(debtToken, flashAmt, data);
        }
    }

    /// @dev The rollover-from-lending callback payload, tagged with the flow it belongs to
    function _encodeLendingPayload(
        FlashLoanProvider protocol,
        bytes memory positionData,
        uint256 collateralAmt,
        ITermMaxMarket newMarket,
        IGearingToken newGt,
        address collateral,
        IERC20 debtToken,
        bytes memory delegationData,
        bytes memory rolloverData
    ) internal pure returns (bytes memory) {
        return abi.encode(
            FlashCallbackKind.ROLLOVER_FROM_LENDING,
            abi.encode(
                protocol,
                positionData,
                collateralAmt,
                newMarket,
                newGt,
                collateral,
                debtToken,
                delegationData,
                rolloverData
            )
        );
    }

    /// @dev type(uint256).max asks for all of the collateral, any other amount above it is a
    /// mismatch between what the caller asked for and what the position holds.
    function _resolveCollateralAmt(uint256 collateralAmt, uint256 suppliedAmt) internal pure returns (uint256) {
        if (collateralAmt == type(uint256).max) return suppliedAmt;
        if (collateralAmt > suppliedAmt) {
            revert RouterErrorsV2.CollateralAmtExceedsPosition(suppliedAmt, collateralAmt);
        }
        return collateralAmt;
    }

    /// @dev Optional one-transaction aave delegation: an aave supply position IS the aToken and
    /// aTokens are EIP-2612 permittable, so the allowance this router needs can be signed instead
    /// of pre-approved. Owner and spender are forced, so the signature can only ever hand the
    /// SIGNER's own aTokens to THIS router.
    function _permitAToken(address aToken, address positionOwner, bytes memory delegationData) internal {
        if (delegationData.length == 0) return;
        (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(delegationData, (uint256, uint256, uint8, bytes32, bytes32));
        IERC20Permit(aToken).permit(positionOwner, address(this), value, deadline, v, r, s);
    }

    /// @dev Optional one-transaction morpho delegation. The authorization is required to hand the
    /// SIGNER's own positions to THIS router, so relaying someone else's signature can not
    /// delegate their positions anywhere else.
    function _authorizeMorpho(IMorpho morpho, address positionOwner, bytes memory delegationData) internal {
        if (delegationData.length == 0) return;
        (Authorization memory auth, Signature memory sig) = abi.decode(delegationData, (Authorization, Signature));
        if (auth.authorizer != positionOwner || auth.authorized != address(this) || !auth.isAuthorized) {
            revert RouterErrorsV2.InvalidDelegation();
        }
        morpho.setAuthorizationWithSig(auth, sig);
    }

    function _rolloverFromLending(
        address lendingPool,
        address positionOwner,
        uint256 flashLoanAmt,
        uint256 premium,
        bytes memory data
    ) internal {
        (
            FlashLoanProvider protocol,
            bytes memory positionData,
            uint256 collateralAmt,
            ITermMaxMarket newMarket,
            IGearingToken newGt,
            address collateral,
            IERC20 debtToken,
            bytes memory delegationData,
            bytes memory rolloverData
        ) = abi.decode(
            data, (FlashLoanProvider, bytes, uint256, ITermMaxMarket, IGearingToken, address, IERC20, bytes, bytes)
        );
        /// @dev Repay the caller's third party debt with the flash borrowed debt token and move
        /// the freed collateral here. The loan IS the repayment budget: as much of the debt as it
        /// covers is repaid and never a wei more, so nothing about the position has to be known
        /// in advance. `positionOwner` comes from transient storage — the account that opened
        /// this flow — never from the payload, so only that account's own position is touched,
        /// whatever allowance or authorization this router holds for someone else.
        debtToken.safeApprove(lendingPool, flashLoanAmt);
        if (protocol == FlashLoanProvider.AAVE) {
            _unwindAave(
                lendingPool, positionOwner, collateral, address(debtToken), flashLoanAmt, collateralAmt, delegationData
            );
        } else {
            _unwindMorpho(
                lendingPool,
                positionOwner,
                collateral,
                address(debtToken),
                positionData,
                flashLoanAmt,
                collateralAmt,
                delegationData
            );
        }
        /// @dev The borrow is exactly what the caller quoted in `swapFtPath` — it does not
        /// depend on how much of the loan the repayment consumed.
        uint256 newGtId = _openTermMaxPosition(newMarket, newGt, positionOwner, collateral, rolloverData);
        uint256 repaymentAmt = flashLoanAmt + premium;
        uint256 debtTokenBalance = debtToken.balanceOf(address(this));
        if (debtTokenBalance < repaymentAmt) revert RouterErrorsV2.RolloverFailed(repaymentAmt, debtTokenBalance);
        /// @dev Everything the flash loan repayment does not need — the part of the loan the debt
        /// did not consume, the caller's debt token buffer, a sale quoted above the cost — is put
        /// straight back into the new position as a repayment instead of being refunded.
        uint256 surplus = debtTokenBalance - repaymentAmt;
        if (surplus != 0) {
            (, uint128 newDebtAmt,) = newGt.loanInfo(newGtId);
            /// @dev It has to be worth strictly less than the new debt. Repaying all of it would
            /// burn the gt and hand the collateral back instead of leaving the caller with the
            /// fixed rate position they asked for, and capping it at the debt would strand the
            /// remainder in this contract — neither is what the caller asked for, so this is a
            /// mismatch in the amounts they passed rather than something to paper over.
            if (surplus >= newDebtAmt) revert RouterErrorsV2.SurplusExceedsNewDebt(newDebtAmt, surplus);
            debtToken.safeApprove(address(newGt), surplus);
            // repay in debt token, bool true means not using ft
            newGt.repay(newGtId, surplus.toUint128(), true);
        }
        debtToken.safeApprove(lendingPool, repaymentAmt);
    }

    /// @dev Repay as much of the caller's own aave debt as the flash loan covers — aave caps the
    /// repayment at what the position owes and returns what it took — and pull the collateral
    /// backing it out of aave.
    function _unwindAave(
        address lendingPool,
        address positionOwner,
        address collateral,
        address debtToken,
        uint256 flashLoanAmt,
        uint256 collateralAmt,
        bytes memory delegationData
    ) internal {
        IAaveV3Pool pool = IAaveV3Pool(lendingPool);
        pool.repay(debtToken, flashLoanAmt, AAVE_VARIABLE_RATE_MODE, positionOwner);
        /// @dev Aave has no withdraw-on-behalf: an aave supply position IS the aToken, so the
        /// owner's aTokens are pulled with the allowance that owner gave this router and burnt
        /// here for the underlying collateral. Aave checks that the leftover position stays
        /// healthy while transferring them out, and burning by type(uint256).max sidesteps the
        /// aToken's scaled balance rounding.
        address aToken = pool.getReserveData(collateral).aTokenAddress;
        _permitAToken(aToken, positionOwner, delegationData);
        collateralAmt = _resolveCollateralAmt(collateralAmt, IERC20(aToken).balanceOf(positionOwner));
        if (collateralAmt != 0) {
            IERC20(aToken).safeTransferFrom(positionOwner, address(this), collateralAmt);
            pool.withdraw(collateral, type(uint256).max, address(this));
        }
    }

    /// @dev Repay as much of the caller's own morpho debt as the flash loan covers and withdraw
    /// the collateral backing it. Morpho neither caps a repayment nor prices one for us, so the
    /// loan is converted into borrow shares and capped at the shares the position actually holds:
    /// the whole debt is burnt share by share when the loan covers it, and no wei of the loan is
    /// overspent when it does not.
    function _unwindMorpho(
        address lendingPool,
        address positionOwner,
        address collateral,
        address debtToken,
        bytes memory positionData,
        uint256 flashLoanAmt,
        uint256 collateralAmt,
        bytes memory delegationData
    ) internal {
        IMorpho morpho = IMorpho(lendingPool);
        Id morphoMarketId = abi.decode(positionData, (Id));
        MarketParams memory marketParams = morpho.idToMarketParams(morphoMarketId);
        if (marketParams.loanToken != debtToken || marketParams.collateralToken != collateral) {
            revert RouterErrorsV2.LendingMarketTokensNotMatch();
        }
        _authorizeMorpho(morpho, positionOwner, delegationData);
        // the repayment below accrues interest anyway, doing it here makes the conversion exact
        morpho.accrueInterest(marketParams);
        (, uint128 borrowShares, uint128 positionCollateral) = morpho.position(morphoMarketId, positionOwner);
        uint256 sharesToRepay;
        {
            (,, uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = morpho.market(morphoMarketId);
            // SharesMathLib.toAssetsUp: what burning every borrow share of the position costs
            uint256 debtAssets = Math.mulDiv(
                borrowShares,
                uint256(totalBorrowAssets) + MORPHO_VIRTUAL_ASSETS,
                uint256(totalBorrowShares) + MORPHO_VIRTUAL_SHARES,
                Math.Rounding.Ceil
            );
            /// @dev A loan that covers that cost burns every share. Converting the loan to shares
            /// instead would round down and leave a share of debt behind, and a position with
            /// debt but no collateral is never healthy, so the withdrawal below would revert.
            /// Anything less is a partial repayment, rounded down so it costs at most the loan.
            sharesToRepay = flashLoanAmt >= debtAssets
                ? borrowShares
                : Math.mulDiv(
                    flashLoanAmt,
                    uint256(totalBorrowShares) + MORPHO_VIRTUAL_SHARES,
                    uint256(totalBorrowAssets) + MORPHO_VIRTUAL_ASSETS
                );
        }
        morpho.repay(marketParams, 0, sharesToRepay, positionOwner, "");
        collateralAmt = _resolveCollateralAmt(collateralAmt, positionCollateral);
        if (collateralAmt != 0) {
            // morpho checks that the leftover position stays healthy
            morpho.withdrawCollateral(marketParams, collateralAmt, positionOwner, address(this));
        }
    }

    /// @dev Delegate issuing and selling the new ft to router v2. The collateral input is this
    /// contract's whole collateral balance — the released collateral plus the caller's optional
    /// additional collateral, all of it goes into the position — and the new gt recipient is
    /// enforced to this contract, so neither can be hijacked by malicious parameters. The sale
    /// proceeds have to come back here to repay the flash loan, so the sell path recipient is
    /// enforced too.
    function _openTermMaxPosition(
        ITermMaxMarket newMarket,
        IGearingToken newGt,
        address positionOwner,
        address collateral,
        bytes memory rolloverData
    ) internal returns (uint256 newGtId) {
        (address routerV2, uint128 maxDebtAmt, SwapPath memory swapFtPath) =
            abi.decode(rolloverData, (address, uint128, SwapPath));
        if (swapFtPath.recipient != address(this)) revert RouterErrorsV2.InvalidSwapRecipient();
        uint256 newCollateralAmt = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeIncreaseAllowance(routerV2, newCollateralAmt);
        newGtId = ITermMaxRouterV2(routerV2)
            .borrowTokenFromCollateral(address(this), newMarket, newCollateralAmt, maxDebtAmt, swapFtPath);
        // forward the new gt to the caller
        newGt.safeTransferFrom(address(this), positionOwner, newGtId, "");
        assembly {
            tstore(T_NEW_GT_STORE, newGtId)
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
