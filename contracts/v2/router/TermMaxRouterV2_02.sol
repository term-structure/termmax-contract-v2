// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
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
import {ITermMaxRouterV2} from "./ITermMaxRouterV2.sol";
import {ITermMaxRouterV2_02, FlashLoanProvider} from "./ITermMaxRouterV2_02.sol";
import {ITermMaxVaultV2} from "../vault/ITermMaxVaultV2.sol";
import {IMorpho} from "../extensions/morpho/IMorpho.sol";
import {IAaveV3Pool} from "../extensions/aave/IAaveV3Pool.sol";
import {RouterErrorsV2} from "../errors/RouterErrorsV2.sol";
import {RouterEventsV2} from "../events/RouterEventsV2.sol";
import {TransferUtilsV2} from "../lib/TransferUtilsV2.sol";
import {WithWhitelistCheck, IWhitelistManager} from "../access/WithWhitelistCheck.sol";
import {VersionV2_0_2} from "../VersionV2_0_2.sol";

/**
 * @title TermMax Router V2.0.2 — flash rollover periphery
 * @author Term Structure Labs
 * @notice Standalone periphery that rolls a GT position (fully or partially) into a new
 *         market, using an external flash loan (Morpho / Aave) as temporary vault
 *         liquidity. It only orchestrates: issuing and selling the new FT is delegated
 *         to the already-audited TermMaxRouterV2 `borrowTokenFromCollateral`, invoked
 *         with backend-built calldata. Kept separate from TermMaxRouterV2 so both stay
 *         within the EIP-170 bytecode limit.
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

    uint256 private constant T_NEW_GT_STORE = 0;
    uint256 private constant T_CALLBACK_ADDRESS_STORE = 1;

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
        uint256 additionalAmt,
        FlashLoanProvider provider,
        address flashLender,
        ITermMaxVaultV2 vault,
        address ftOrder,
        bytes memory rolloverData
    ) external nonReentrant whenNotPaused onlyWhitelisted(address(market)) returns (uint256 newGtId) {
        (,, IGearingToken gtToken, address collateral, IERC20 debtToken) = market.tokens();
        address firstCaller = _msgSender();
        assembly {
            // the flash lender is the only address allowed to call back
            tstore(T_CALLBACK_ADDRESS_STORE, flashLender)
            // clear ts stograge
            tstore(T_NEW_GT_STORE, 0)
        }
        // additional debt token to cover the rollover cost(ft discount, issue fee, flash loan premium)
        if (additionalAmt != 0) {
            debtToken.safeTransferFrom(firstCaller, address(this), additionalAmt);
        }
        // pull the gt to act as its owner, it is returned to the caller at the end
        gtToken.safeTransferFrom(firstCaller, address(this), gtId, "");
        {
            (, uint128 debtAmt,) = gtToken.loanInfo(gtId);
            if (repayAmt > debtAmt) {
                repayAmt = debtAmt;
            }
        }
        // the exact assets required to mint just enough shares to redeem `repayAmt` of ft
        uint256 flashLoanAmt = IERC4626(address(vault)).previewMint(IERC4626(address(vault)).previewWithdraw(repayAmt));
        bytes memory data = abi.encode(market, gtId, repayAmt, vault, ftOrder, rolloverData);
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

    /// @dev Morpho flash loan callback
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external onlyCallbackAddress {
        _flashRollover(_msgSender(), assets, 0, data);
    }

    /// @dev Aave V3 flash loan callback
    function executeOperation(address, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        onlyCallbackAddress
        returns (bool)
    {
        if (initiator != address(this)) revert RouterErrorsV2.InvalidFlashLoanInitiator();
        _flashRollover(_msgSender(), amount, premium, params);
        return true;
    }

    function _flashRollover(address flashLender, uint256 flashLoanAmt, uint256 premium, bytes memory data) internal {
        (
            ITermMaxMarket market,
            uint256 gtId,
            uint128 repayAmt,
            ITermMaxVaultV2 vault,
            address ftOrder,
            bytes memory rolloverData
        ) = abi.decode(data, (ITermMaxMarket, uint256, uint128, ITermMaxVaultV2, address, bytes));
        (address routerV2, uint256 removedCollateral, bytes memory borrowCalldata) =
            abi.decode(rolloverData, (address, uint256, bytes));
        /// @dev Only the borrow function of router v2 can be composed here
        if (bytes4(borrowCalldata) != ITermMaxRouterV2.borrowTokenFromCollateral.selector) {
            revert RouterErrorsV2.InvalidBorrowCalldata();
        }

        (IERC20 ft,, IGearingToken gt, address collateral, IERC20 debtToken) = market.tokens();
        {
            // mint the exact shares needed to redeem `repayAmt` of the old market's ft
            debtToken.safeIncreaseAllowance(address(vault), flashLoanAmt);
            IERC4626(address(vault)).mint(IERC4626(address(vault)).previewWithdraw(repayAmt), address(this));
            // burn the shares to redeem the old market's ft from the vault order
            vault.withdrawFts(ftOrder, repayAmt, address(this), address(this));
            // repay(maybe partially) the old gt in ft and move the freed collateral here,
            // the gt is not burned and the leftover position stays healthy(checked by the gt)
            ft.safeIncreaseAllowance(address(gt), repayAmt);
            // repay in ft, bool false means not using debt token
            IGearingTokenV2(address(gt))
                .repayAndRemoveCollateral(gtId, repayAmt, false, address(this), abi.encode(removedCollateral));
        }
        /// @dev Delegate issuing and selling the new ft to router v2 with the backend-built
        /// calldata. The backend must set the sell path recipient to this contract so the
        /// sale proceeds come back here to repay the flash loan.
        uint256 collateralAmt = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeIncreaseAllowance(routerV2, collateralAmt);
        bytes memory returnData = Address.functionCall(routerV2, borrowCalldata);
        uint256 newGtId = abi.decode(returnData, (uint256));
        assembly {
            tstore(T_NEW_GT_STORE, newGtId)
        }
        // approve the lender to pull the flash loan repayment
        debtToken.safeIncreaseAllowance(flashLender, flashLoanAmt + premium);
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
