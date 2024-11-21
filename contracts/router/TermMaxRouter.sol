// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {ITermMaxMarket} from "../core/ITermMaxMarket.sol";
import {ITermMaxRouter} from "./ITermMaxRouter.sol";
import {MathLib} from "../core/lib/MathLib.sol";
import {IMintableERC20} from "../core/tokens/IMintableERC20.sol";
import {MarketConfig} from "../core/storage/TermMaxStorage.sol";
import {Constants} from "../core/lib/Constants.sol";
import {IFlashLoanReceiver} from "../core/IFlashLoanReceiver.sol";
import {IFlashRepayer} from "../core/tokens/IFlashRepayer.sol";
import {IGearingToken} from "../core/tokens/IGearingToken.sol";
import {SwapUnit, ISwapAdapter} from "./ISwapAdapter.sol";

contract TermMaxRouter is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    IFlashLoanReceiver,
    IFlashRepayer,
    ITermMaxRouter
{
    using Address for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for uint128;
    using MathLib for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;

    bytes32 OPERATOR_ROLE = keccak256(abi.encode("OPERATOR_ROLE"));

    mapping(address => bool) public marketWhitelist;
    modifier ensureMarketWhitelist(address market) {
        require(marketWhitelist[market], "Market not whitelisted");
        _;
    }

    modifier ensureGtWhitelist(address gt) {
        address market = IGearingToken(gt).marketAddr();
        require(marketWhitelist[market], "Market of Gt not whitelisted");
        (, , , , IGearingToken gt_, , ) = ITermMaxMarket(market).tokens();
        require(address(gt_) == gt, "Gt not whitelisted");
        _;
    }

    mapping(address => bool) public swapperWhitelist;
    modifier ensureSwapperWhitelist(address swapper) {
        require(swapperWhitelist[swapper], "Swapper not whitelisted");
        _;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function initialize(address defaultAdmin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(OPERATOR_ROLE, defaultAdmin);
        _pause();
    }

    function togglePause(bool isPause) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isPause) {
            _pause();
        } else {
            _unpause();
        }
    }

    function setMarketWhitelist(
        address market,
        bool isWhitelist
    ) external onlyRole(OPERATOR_ROLE) {
        marketWhitelist[market] = isWhitelist;
    }

    function setSwapperWhitelist(
        address swapper,
        bool isWhitelist
    ) external onlyRole(OPERATOR_ROLE) {
        swapperWhitelist[swapper] = isWhitelist;
    }

    /** Leverage Market */
    function swapExactTokenForFt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minFtOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netFtOut)
    {
        (IMintableERC20 ft, , , , , , IERC20 underlying) = market.tokens();

        _transferToSelfAndApproveSpender(
            underlying,
            msg.sender,
            address(market),
            tokenInAmt
        );
        (netFtOut) = market.buyFt(tokenInAmt, minFtOut);
        ft.transfer(receiver, netFtOut);

        emit Swap(
            market,
            address(underlying),
            address(ft),
            msg.sender,
            receiver,
            tokenInAmt,
            netFtOut,
            minFtOut
        );
    }

    function swapExactFtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 minTokenOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (IMintableERC20 ft, , , , , , IERC20 underlying) = market.tokens();
        ft.safeTransferFrom(msg.sender, address(this), ftInAmt);

        ft.safeIncreaseAllowance(address(market), ftInAmt);
        (netTokenOut) = market.sellFt(ftInAmt, minTokenOut);
        underlying.transfer(receiver, netTokenOut);

        emit Swap(
            market,
            address(ft),
            address(underlying),
            msg.sender,
            receiver,
            ftInAmt,
            netTokenOut,
            minTokenOut
        );
    }

    function swapExactTokenForXt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minXtOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netXtOut)
    {
        (, IMintableERC20 xt, , , , , IERC20 underlying) = market.tokens();
        underlying.safeTransferFrom(msg.sender, address(this), tokenInAmt);

        underlying.safeIncreaseAllowance(address(market), tokenInAmt);
        (netXtOut) = market.buyXt(tokenInAmt, minXtOut);
        xt.transfer(receiver, netXtOut);

        emit Swap(
            market,
            address(underlying),
            address(xt),
            msg.sender,
            receiver,
            tokenInAmt,
            netXtOut.toUint128(),
            minXtOut
        );
    }

    function swapExactXtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 minTokenOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (, IMintableERC20 xt, , , , , IERC20 underlying) = market.tokens();
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);

        xt.safeIncreaseAllowance(address(market), xtInAmt);
        (netTokenOut) = market.sellXt(xtInAmt, minTokenOut);
        underlying.transfer(receiver, netTokenOut);

        emit Swap(
            market,
            address(xt),
            address(underlying),
            msg.sender,
            receiver,
            xtInAmt,
            netTokenOut,
            minTokenOut
        );
    }

    function provideLiquidity(
        address receiver,
        ITermMaxMarket market,
        uint256 underlyingAmt
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt)
    {
        (
            ,
            ,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            ,
            ,
            IERC20 underlying
        ) = market.tokens();
        _transferToSelfAndApproveSpender(
            underlying,
            msg.sender,
            address(market),
            underlyingAmt
        );

        (lpFtOutAmt, lpXtOutAmt) = market.provideLiquidity(underlyingAmt);
        lpFt.transfer(receiver, lpFtOutAmt);
        lpXt.transfer(receiver, lpXtOutAmt);

        emit AddLiquidity(
            market,
            address(underlying),
            msg.sender,
            receiver,
            underlyingAmt,
            lpFtOutAmt,
            lpXtOutAmt
        );
    }

    function withdrawLiquidityToFtXt(
        address receiver,
        ITermMaxMarket market,
        uint256 lpFtInAmt,
        uint256 lpXtInAmt,
        uint256 minFtOut,
        uint256 minXtOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 ftOutAmt, uint256 xtOutAmt)
    {
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            ,
            ,

        ) = market.tokens();

        lpFt.safeTransferFrom(msg.sender, address(this), lpFtInAmt);
        lpXt.safeTransferFrom(msg.sender, address(this), lpXtInAmt);

        lpFt.safeIncreaseAllowance(address(market), lpFtInAmt);
        lpXt.safeIncreaseAllowance(address(market), lpXtInAmt);

        (ftOutAmt, xtOutAmt) = market.withdrawLp(
            lpFtInAmt.toUint128(),
            lpXtInAmt.toUint128()
        );
        ft.transfer(receiver, ftOutAmt);
        xt.transfer(receiver, xtOutAmt);

        if (ftOutAmt < minFtOut) {
            revert("Slippage: INSUFFICIENT_FT_OUT");
        }
        if (xtOutAmt < minXtOut) {
            revert("Slippage: INSUFFICIENT_XT_OUT");
        }

        emit WithdrawLiquidityToXtFt(
            market,
            msg.sender,
            receiver,
            lpFtInAmt,
            lpXtInAmt,
            ftOutAmt,
            xtOutAmt,
            minFtOut,
            minXtOut
        );
    }

    function withdrawLiquidityToToken(
        address receiver,
        ITermMaxMarket market,
        uint256 lpFtInAmt,
        uint256 lpXtInAmt,
        uint256 minTokenOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            ,
            ,
            IERC20 underlying
        ) = market.tokens();

        lpFt.safeTransferFrom(msg.sender, address(this), lpFtInAmt);
        lpXt.safeTransferFrom(msg.sender, address(this), lpXtInAmt);

        lpFt.safeIncreaseAllowance(address(market), lpFtInAmt);
        lpXt.safeIncreaseAllowance(address(market), lpXtInAmt);
        // NOTE: TermMaxRouter get FT/XT token first and then sell FT/XT to underlying
        (uint128 ftOutAmt, uint128 xtOutAmt) = market.withdrawLp(
            lpFtInAmt.toUint128(),
            lpXtInAmt.toUint128()
        );
        // NOTE: swap all FT and XT to underlying, then allow all ftOutAmt and xtOutAmt to market
        ft.safeIncreaseAllowance(address(market), ftOutAmt);
        xt.safeIncreaseAllowance(address(market), xtOutAmt);

        netTokenOut = _redeemFtAndXtToUnderlying(
            market,
            receiver,
            underlying,
            ftOutAmt,
            xtOutAmt
        );
        if (netTokenOut < minTokenOut) {
            revert("Slippage: INSUFFICIENT_TOKEN_OUT");
        }

        emit WithdrawLiquidtyToToken(
            market,
            address(underlying),
            msg.sender,
            receiver,
            lpFtInAmt,
            lpXtInAmt,
            netTokenOut,
            minTokenOut
        );
    }

    function _redeemFtAndXtToUnderlying(
        ITermMaxMarket market,
        address receiver,
        IERC20 underlying,
        uint128 ftOutAmt,
        uint128 xtOutAmt
    ) internal returns (uint256 underlyingAmtOut) {
        MarketConfig memory config = market.config();
        (uint128 redeemFtAmt, uint128 redeemXtAmt) = _calculateRedeemAmounts(
            ftOutAmt,
            xtOutAmt,
            config.initialLtv
        );
        market.redeemFtAndXtToUnderlying(redeemXtAmt);
        underlyingAmtOut = redeemXtAmt;
        uint128 remainFtAmt = ftOutAmt - redeemFtAmt;
        if (remainFtAmt > 0) {
            underlyingAmtOut += market.sellFt(remainFtAmt, 0);
        }

        uint128 remainXtAmt = xtOutAmt - redeemXtAmt;
        if (remainXtAmt > 0) {
            underlyingAmtOut += market.sellXt(remainXtAmt, 0);
        }
        underlying.transfer(receiver, underlyingAmtOut);
    }

    function _calculateRedeemAmounts(
        uint128 ftOutAmt,
        uint128 xtOutAmt,
        uint128 initialLtv
    ) internal pure returns (uint128 redeemFtAmt, uint128 redeemXtAmt) {
        uint128 requiredFtAmt = (xtOutAmt * initialLtv) /
            Constants.DECIMAL_BASE.toUint128();
        uint128 requiredXtAmt = (ftOutAmt *
            Constants.DECIMAL_BASE.toUint128()) / initialLtv;

        redeemFtAmt = ftOutAmt < requiredFtAmt ? ftOutAmt : requiredFtAmt;
        redeemXtAmt = xtOutAmt < requiredXtAmt ? xtOutAmt : requiredXtAmt;
    }

    function redeem(
        address receiver,
        ITermMaxMarket market,
        uint256[4] calldata amountArray,
        uint256 minCollOut,
        uint256 minTokenOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netCollOut, uint256 netTokenOut)
    {
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            ,
            address collateralAddr,
            IERC20 underlying
        ) = market.tokens();
        if (amountArray[0] > 0) {
            _transferToSelfAndApproveSpender(
                IERC20(ft),
                msg.sender,
                address(market),
                amountArray[0]
            );
        }
        if (amountArray[1] > 0) {
            _transferToSelfAndApproveSpender(
                IERC20(xt),
                msg.sender,
                address(market),
                amountArray[1]
            );
        }
        if (amountArray[2] > 0) {
            _transferToSelfAndApproveSpender(
                IERC20(lpFt),
                msg.sender,
                address(market),
                amountArray[2]
            );
        }
        if (amountArray[3] > 0) {
            _transferToSelfAndApproveSpender(
                IERC20(lpXt),
                msg.sender,
                address(market),
                amountArray[3]
            );
        }

        market.redeem(amountArray);

        IERC20 collateral = IERC20(collateralAddr);
        netCollOut = _balanceOf(collateral, address(this));
        if (netCollOut < minCollOut) {
            revert("Slippage: INSUFFICIENT_COLLATERAL_OUT");
        }
        collateral.safeTransfer(receiver, netCollOut);

        netTokenOut = _balanceOf(underlying, address(this));
        if (netTokenOut < minTokenOut) {
            revert("Slippage: INSUFFICIENT_TOKEN_OUT");
        }
        underlying.safeTransfer(receiver, netTokenOut);

        emit Redeem(
            market,
            address(underlying),
            msg.sender,
            receiver,
            amountArray,
            netTokenOut,
            netCollOut
        );
    }

    function leverageFromToken(
        address receiver,
        ITermMaxMarket market,
        uint256 tokenInAmt, // underlying to buy collateral
        uint256 tokenToBuyXtAmt, // underlying to buy Xt
        uint256 maxLtv,
        uint256 minXtAmt,
        SwapUnit[] memory units
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 gtId, uint256 netXtOut)
    {
        (
            ,
            IMintableERC20 xt,
            ,
            ,
            IGearingToken gt,
            ,
            IERC20 underlying
        ) = market.tokens();
        underlying.transferFrom(
            msg.sender,
            address(this),
            tokenToBuyXtAmt + tokenInAmt
        );
        underlying.approve(address(market), tokenToBuyXtAmt);
        uint256 _netXtOut = market.buyXt(
            tokenToBuyXtAmt.toUint128(),
            minXtAmt.toUint128()
        );
        netXtOut = _netXtOut;
        bytes memory callbackData = abi.encode(address(gt), netXtOut, units);
        xt.safeIncreaseAllowance(address(market), netXtOut);
        gtId = market.leverageByXt(
            address(this),
            netXtOut.toUint128(),
            callbackData
        );
        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        require(ltv <= maxLtv, "Slippage: ltv bigger than expected ltv");

        gt.safeTransferFrom(address(this), receiver, gtId);

        emit IssueGt(
            market,
            address(underlying),
            msg.sender,
            receiver,
            gtId,
            tokenInAmt,
            netXtOut,
            _decodeAmount(collateralData),
            maxLtv,
            minXtAmt
        );
    }

    function leverageFromXt(
        address receiver,
        ITermMaxMarket market,
        uint256 xtInAmt,
        uint256 tokenInAmt, // underlying
        uint256 maxLtv,
        SwapUnit[] memory units
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 gtId)
    {
        (
            ,
            IMintableERC20 xt,
            ,
            ,
            IGearingToken gt,
            ,
            IERC20 underlying
        ) = market.tokens();
        _transferToSelfAndApproveSpender(
            xt,
            msg.sender,
            address(market),
            xtInAmt
        );

        underlying.safeTransferFrom(msg.sender, address(this), tokenInAmt);

        bytes memory callbackData = abi.encode(address(gt), tokenInAmt, units);
        gtId = market.leverageByXt(
            address(this),
            xtInAmt.toUint128(),
            callbackData
        );
        gt.safeTransferFrom(address(this), receiver, gtId);

        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        require(ltv <= maxLtv, "Slippage: ltv bigger than expected ltv");

        emit IssueGt(
            market,
            address(underlying),
            msg.sender,
            receiver,
            gtId,
            xtInAmt,
            xtInAmt,
            _decodeAmount(collateralData),
            maxLtv,
            xtInAmt
        );
    }

    /** Lending Market */
    function borrowTokenFromCollateral(
        address receiver,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 maxDebtAmt,
        uint256 borrowAmt
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 gtId)
    {
        (
            IMintableERC20 ft,
            ,
            ,
            ,
            IGearingToken gt,
            address collateralAddr,
            IERC20 underlying
        ) = market.tokens();

        _transferToSelfAndApproveSpender(
            IERC20(collateralAddr),
            msg.sender,
            address(gt),
            collInAmt
        );

        return
            _borrow(
                market,
                ft,
                gt,
                underlying,
                receiver,
                maxDebtAmt,
                collInAmt,
                borrowAmt
            );
    }

    function _borrow(
        ITermMaxMarket market,
        IMintableERC20 ft,
        IGearingToken gt,
        IERC20 underlying,
        address receiver,
        uint256 maxDebtAmt,
        uint256 collInAmt,
        uint256 borrowAmt
    ) internal returns (uint256) {
        /**
         * 1. MintGT with Collateral, and get GT, FT
         * 2. Sell FT to get UnderlyingToken
         * 3. Transfer UnderlyingToken and GT to Receiver
         */
        (uint256 gtId, uint128 netFtOut) = market.issueFt(
            maxDebtAmt.toUint128(),
            _encodeAmount(collInAmt)
        );

        ft.safeIncreaseAllowance(address(market), netFtOut);
        uint256 netTokenOut = market.sellFt(netFtOut, borrowAmt.toUint128());
        // NOTE: if netTokenOut > borrowAmt, repay
        uint256 repayAmt = netTokenOut - borrowAmt;
        if (repayAmt > 0) {
            underlying.safeIncreaseAllowance(address(gt), repayAmt);
            gt.repay(gtId, repayAmt.toUint128(), true);
        }

        underlying.safeTransfer(receiver, borrowAmt);
        gt.transferFrom(address(this), receiver, gtId);

        emit Borrow(
            market,
            address(underlying),
            msg.sender,
            receiver,
            gtId,
            collInAmt,
            maxDebtAmt - repayAmt,
            borrowAmt
        );

        return gtId;
    }

    function repay(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 repayAmt
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (, , , , IGearingToken gt, , IERC20 underlying) = market.tokens();
        underlying.safeTransferFrom(msg.sender, address(this), repayAmt);
        underlying.safeIncreaseAllowance(address(gt), repayAmt);
        gt.repay(gtId, repayAmt.toUint128(), true);

        emit Repay(market, false, address(underlying), gtId, repayAmt);
    }

    function flashRepayFromColl(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        SwapUnit[] memory units
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (, , , , IGearingToken gt, , IERC20 underlying) = market.tokens();

        gt.flashRepay(gtId, abi.encode(units));
        // transfer remainning underlying token
        underlying.transfer(receiver, underlying.balanceOf(address(this)));
    }

    function repayFromFt(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 ftInAmt
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (IMintableERC20 ft, , , , IGearingToken gt, , ) = market.tokens();
        ft.safeTransferFrom(msg.sender, address(this), ftInAmt);
        ft.safeIncreaseAllowance(address(gt), ftInAmt);
        gt.repay(gtId, ftInAmt.toUint128(), false);

        emit Repay(market, true, address(ft), gtId, ftInAmt);
    }

    function repayByTokenThroughFt(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 tokenInAmt,
        uint256 minFtOutToRepay
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (
            IMintableERC20 ft,
            ,
            ,
            ,
            IGearingToken gt,
            ,
            IERC20 underlying
        ) = market.tokens();
        underlying.safeTransferFrom(msg.sender, address(this), tokenInAmt);
        underlying.safeIncreaseAllowance(address(market), tokenInAmt);

        uint256 netFtOut = market.buyFt(
            tokenInAmt.toUint128(),
            minFtOutToRepay.toUint128()
        );
        if (netFtOut < minFtOutToRepay) {
            revert("Slippage: INSUFFICIENT_FT_OUT");
        }
        (, uint128 debtAmt, , ) = gt.loanInfo(gtId);
        if (debtAmt == 0) {
            revert("Debt is already repaid");
        }

        if (netFtOut > debtAmt) {
            ft.safeIncreaseAllowance(address(gt), debtAmt);
            gt.repay(gtId, debtAmt, false);
            ft.safeTransfer(receiver, netFtOut - debtAmt);
        } else {
            ft.safeIncreaseAllowance(address(gt), netFtOut);
            gt.repay(gtId, netFtOut.toUint120(), false);
        }

        emit Repay(market, false, address(underlying), gtId, tokenInAmt);
    }

    function mergeGt(
        ITermMaxMarket market,
        uint256[] memory ids
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 newId)
    {
        (, , , , IGearingToken gt, , ) = market.tokens();
        return gt.merge(ids);
    }

    function addCollateral(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 addCollateralAmt
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (, , , , IGearingToken gt, address collateral, ) = market.tokens();
        _transferToSelfAndApproveSpender(
            IERC20(collateral),
            msg.sender,
            address(gt),
            addCollateralAmt
        );
        gt.addCollateral(gtId, _encodeAmount(addCollateralAmt));
    }

    function removeCollateral(
        ITermMaxMarket market,
        uint256 gtId,
        uint256 removeCollateralAmt
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (, , , , IGearingToken gt, , ) = market.tokens();
        gt.removeCollateral(gtId, _encodeAmount(removeCollateralAmt));
    }

    /// @dev Market flash leverage falshloan callback
    function executeOperation(
        address,
        IERC20,
        uint256 amount,
        bytes calldata data
    )
        external
        ensureMarketWhitelist(msg.sender)
        returns (bytes memory collateralData)
    {
        (address gt, uint256 tokenInAmt, SwapUnit[] memory units) = abi.decode(
            data,
            (address, uint256, SwapUnit[])
        );
        uint totalAmount = amount + tokenInAmt;
        collateralData = _doSwap(abi.encode(totalAmount), units);
        SwapUnit memory lastUnit = units[units.length - 1];
        // encode collateral data and approve
        bytes memory approvalData = abi.encodeWithSelector(
            ISwapAdapter.approveOutputToken.selector,
            lastUnit.tokenOut,
            gt,
            collateralData
        );
        (bool success, ) = lastUnit.adapter.delegatecall(approvalData);
        require(success, "Swap: Approve token failed");
    }

    function _balanceOf(
        IERC20 token,
        address account
    ) internal view returns (uint256) {
        return token.balanceOf(account);
    }

    function _transferToSelfAndApproveSpender(
        IERC20 token,
        address from,
        address spender,
        uint256 amount
    ) internal {
        token.safeTransferFrom(from, address(this), amount);
        token.safeIncreaseAllowance(spender, amount);
    }

    function _encodeAmount(
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(amount);
    }

    function _decodeAmount(
        bytes memory collateralData
    ) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint256));
    }

    /// @dev Gt flash repay flashloan callback
    function executeOperation(
        address owner,
        IERC20 debtToken,
        uint128 debtAmt,
        address,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external override ensureGtWhitelist(msg.sender) {
        SwapUnit[] memory units = abi.decode(callbackData, (SwapUnit[]));

        // transfer collateral
        bytes memory dataToTransferFrom = abi.encodeWithSelector(
            ISwapAdapter.transferInputTokenFrom.selector,
            units[0].tokenIn,
            owner,
            address(this),
            collateralData
        );
        (bool success, ) = units[0].adapter.delegatecall(dataToTransferFrom);
        require(success, "Swap: Transfer collateral from owner failed");

        // do swap
        _doSwap(collateralData, units);
        debtToken.approve(msg.sender, debtAmt);
    }

    function _doSwap(
        bytes memory inputData,
        SwapUnit[] memory units
    ) internal returns (bytes memory outData) {
        for (uint i = 0; i < units.length; ++i) {
            if (!swapperWhitelist[units[i].adapter]) {
                revert("Invalid adapter");
            }
            // encode datas
            bytes memory dataToSwap = abi.encodeWithSelector(
                ISwapAdapter.swap.selector,
                units[i].tokenIn,
                units[i].tokenOut,
                inputData,
                units[i].swapData
            );

            // delegatecall
            (bool success, bytes memory returnData) = units[i]
                .adapter
                .delegatecall(dataToSwap);

            require(success, "Swap: Failed");
            inputData = abi.decode(returnData, (bytes));
        }
        outData = inputData;
    }
}
