// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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
    ITermMaxRouter,
    IERC721Receiver
{
    using Address for address;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for uint128;
    using MathLib for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;

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
        (, , , , IGearingToken gt_, , ) = ITermMaxMarket(market).tokens();
        if (address(gt_) != gt) {
            revert GtNotWhitelisted(gt);
        }
        _;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin) public initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __Ownable_init(defaultAdmin);

        _pause();
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function togglePause(bool isPause) external onlyOwner {
        if (isPause) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function setMarketWhitelist(
        address market,
        bool isWhitelist
    ) external onlyOwner {
        marketWhitelist[market] = isWhitelist;
        emit UpdateMarketWhiteList(market, isWhitelist);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function setAdapterWhitelist(
        address adapter,
        bool isWhitelist
    ) external onlyOwner {
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
        returns (
            IERC20[6] memory tokens,
            uint256[6] memory balances,
            address gtAddr,
            uint256[] memory gtIds
        )
    {
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingToken gt,
            address collateral,
            IERC20 underlying
        ) = market.tokens();
        tokens[0] = ft;
        tokens[1] = xt;
        tokens[2] = lpFt;
        tokens[3] = lpXt;
        tokens[4] = IERC20(collateral);
        tokens[5] = underlying;
        for (uint i = 0; i < 6; ++i) {
            balances[i] = tokens[i].balanceOf(owner);
        }
        gtAddr = address(gt);
        uint balance = IERC721Enumerable(gtAddr).balanceOf(owner);
        gtIds = new uint256[](balance);
        for (uint i = 0; i < balance; ++i) {
            gtIds[i] = IERC721Enumerable(gtAddr).tokenOfOwnerByIndex(owner, i);
        }
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function swapExactTokenForFt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minFtOut,
        uint32 lsf
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
        (netFtOut) = market.buyFt(tokenInAmt, minFtOut, lsf);
        ft.safeTransfer(receiver, netFtOut);
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

    /**
     * @inheritdoc ITermMaxRouter
     */
    function swapExactFtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 ftInAmt,
        uint128 minTokenOut,
        uint32 lsf
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (IMintableERC20 ft, , , , , , IERC20 underlying) = market.tokens();

        _transferToSelfAndApproveSpender(
            ft,
            msg.sender,
            address(market),
            ftInAmt
        );

        (netTokenOut) = market.sellFt(ftInAmt, minTokenOut, lsf);
        underlying.safeTransfer(receiver, netTokenOut);

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

    /**
     * @inheritdoc ITermMaxRouter
     */
    function swapExactTokenForXt(
        address receiver,
        ITermMaxMarket market,
        uint128 tokenInAmt,
        uint128 minXtOut,
        uint32 lsf
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netXtOut)
    {
        (, IMintableERC20 xt, , , , , IERC20 underlying) = market.tokens();
        underlying.safeTransferFrom(msg.sender, address(this), tokenInAmt);

        underlying.safeIncreaseAllowance(address(market), tokenInAmt);
        (netXtOut) = market.buyXt(tokenInAmt, minXtOut, lsf);
        xt.safeTransfer(receiver, netXtOut);

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

    /**
     * @inheritdoc ITermMaxRouter
     */
    function swapExactXtForToken(
        address receiver,
        ITermMaxMarket market,
        uint128 xtInAmt,
        uint128 minTokenOut,
        uint32 lsf
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (, IMintableERC20 xt, , , , , IERC20 underlying) = market.tokens();
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);

        xt.safeIncreaseAllowance(address(market), xtInAmt);
        (netTokenOut) = market.sellXt(xtInAmt, minTokenOut, lsf);
        underlying.safeTransfer(receiver, netTokenOut);

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

    /**
     * @inheritdoc ITermMaxRouter
     */
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

        (lpFtOutAmt, lpXtOutAmt) = market.provideLiquidity(
            underlyingAmt.toUint128()
        );
        lpFt.safeTransfer(receiver, lpFtOutAmt);
        lpXt.safeTransfer(receiver, lpXtOutAmt);

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

    /**
     * @inheritdoc ITermMaxRouter
     */
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

        (ftOutAmt, xtOutAmt) = market.withdrawLiquidity(
            lpFtInAmt.toUint128(),
            lpXtInAmt.toUint128()
        );

        if (ftOutAmt < minFtOut) {
            revert InsufficientTokenOut(address(ft), minFtOut, ftOutAmt);
        }
        if (xtOutAmt < minXtOut) {
            revert InsufficientTokenOut(address(xt), minXtOut, xtOutAmt);
        }

        ft.safeTransfer(receiver, ftOutAmt);
        xt.safeTransfer(receiver, xtOutAmt);

        emit WithdrawLiquidityToXtFt(
            market,
            msg.sender,
            receiver,
            lpFtInAmt,
            lpXtInAmt,
            ftOutAmt,
            xtOutAmt
        );
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function withdrawLiquidityToToken(
        address receiver,
        ITermMaxMarket market,
        uint256 lpFtInAmt,
        uint256 lpXtInAmt,
        uint256 minTokenOut,
        uint32 lsf
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
        (uint128 ftOutAmt, uint128 xtOutAmt) = market.withdrawLiquidity(
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
            xtOutAmt,
            lsf
        );
        if (netTokenOut < minTokenOut) {
            revert InsufficientTokenOut(
                address(underlying),
                minTokenOut,
                netTokenOut
            );
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
        uint128 xtOutAmt,
        uint32 lsf
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
            underlyingAmtOut += market.sellFt(remainFtAmt, 0, lsf);
        }

        uint128 remainXtAmt = xtOutAmt - redeemXtAmt;
        if (remainXtAmt > 0) {
            underlyingAmtOut += market.sellXt(remainXtAmt, 0, lsf);
        }
        underlying.safeTransfer(receiver, underlyingAmtOut);
    }

    function _calculateRedeemAmounts(
        uint128 ftOutAmt,
        uint128 xtOutAmt,
        uint128 initialLtv
    ) internal pure returns (uint128 redeemFtAmt, uint128 redeemXtAmt) {
        uint128 requiredFtAmt = (xtOutAmt *
            initialLtv +
            Constants.DECIMAL_BASE.toUint128() -
            1) / Constants.DECIMAL_BASE.toUint128();
        uint128 requiredXtAmt = (ftOutAmt *
            Constants.DECIMAL_BASE.toUint128()) / initialLtv;

        redeemFtAmt = ftOutAmt < requiredFtAmt ? ftOutAmt : requiredFtAmt;
        redeemXtAmt = xtOutAmt < requiredXtAmt ? xtOutAmt : requiredXtAmt;
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
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
            revert InsufficientTokenOut(
                address(collateral),
                minCollOut,
                netCollOut
            );
        }
        collateral.safeTransfer(receiver, netCollOut);

        netTokenOut = _balanceOf(underlying, address(this));
        if (netTokenOut < minTokenOut) {
            revert InsufficientTokenOut(
                address(underlying),
                minTokenOut,
                netTokenOut
            );
        }
        underlying.safeTransfer(receiver, netTokenOut);

        emit Redeem(
            market,
            msg.sender,
            receiver,
            amountArray,
            netTokenOut,
            netCollOut
        );
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function leverageFromToken(
        address receiver,
        ITermMaxMarket market,
        uint256 tokenInAmt, // underlying to buy collateral
        uint256 tokenToBuyXtAmt, // underlying to buy Xt
        uint256 maxLtv,
        uint256 minXtAmt,
        SwapUnit[] memory units,
        uint32 lsf
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
        underlying.safeTransferFrom(
            msg.sender,
            address(this),
            tokenToBuyXtAmt + tokenInAmt
        );
        underlying.safeIncreaseAllowance(address(market), tokenToBuyXtAmt);
        netXtOut = market.buyXt(
            tokenToBuyXtAmt.toUint128(),
            minXtAmt.toUint128(),
            lsf
        );
        bytes memory callbackData = abi.encode(address(gt), tokenInAmt, units);
        xt.safeIncreaseAllowance(address(market), netXtOut);
        gtId = market.leverageByXt(
            address(this),
            netXtOut.toUint128(),
            callbackData
        );
        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv.toUint128(), ltv);
        }
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
            ltv
        );
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
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
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(maxLtv.toUint128(), ltv);
        }

        emit IssueGt(
            market,
            address(underlying),
            msg.sender,
            receiver,
            gtId,
            xtInAmt,
            xtInAmt,
            _decodeAmount(collateralData),
            ltv
        );
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function borrowTokenFromCollateral(
        address receiver,
        ITermMaxMarket market,
        uint256 collInAmt,
        uint256 maxDebtAmt,
        uint256 borrowAmt,
        uint32 lsf
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
                borrowAmt,
                lsf
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
        uint256 borrowAmt,
        uint32 lsf
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
        uint256 netTokenOut = market.sellFt(
            netFtOut,
            borrowAmt.toUint128(),
            lsf
        );
        // NOTE: if netTokenOut > borrowAmt, repay
        uint256 repayAmt = netTokenOut - borrowAmt;
        if (repayAmt > 0) {
            underlying.safeIncreaseAllowance(address(gt), repayAmt);
            gt.repay(gtId, repayAmt.toUint128(), true);
        }

        underlying.safeTransfer(receiver, borrowAmt);
        gt.safeTransferFrom(address(this), receiver, gtId);

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

    /**
     * @inheritdoc ITermMaxRouter
     */
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

    /**
     * @inheritdoc ITermMaxRouter
     */
    function flashRepayFromColl(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        bool byUnderlying,
        SwapUnit[] memory units,
        uint32 lsf
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (
            IMintableERC20 ft,
            ,
            ,
            ,
            IGearingToken gt,
            ,
            IERC20 underlying
        ) = market.tokens();
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        gt.flashRepay(gtId, byUnderlying, abi.encode(market, ft, units, lsf));
        if (byUnderlying) {
            // SafeTransfer remainning underlying token
            netTokenOut = underlying.balanceOf(address(this));
            underlying.safeTransfer(receiver, netTokenOut);
        } else {
            // Swap remainning ft to underlying token
            netTokenOut = ft.balanceOf(address(this));
            ft.safeIncreaseAllowance(address(market), netTokenOut);
            netTokenOut = market.sellFt(netTokenOut.toUint128(), 0, lsf);
            underlying.safeTransfer(receiver, netTokenOut);
        }
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
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

    /**
     * @inheritdoc ITermMaxRouter
     */
    function repayByTokenThroughFt(
        address receiver,
        ITermMaxMarket market,
        uint256 gtId,
        uint256 tokenInAmt,
        uint256 minFtOutToRepay,
        uint32 lsf
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
        _transferToSelfAndApproveSpender(
            underlying,
            msg.sender,
            address(market),
            tokenInAmt
        );

        uint256 netFtOut = market.buyFt(
            tokenInAmt.toUint128(),
            minFtOutToRepay.toUint128(),
            lsf
        );
        if (netFtOut < minFtOutToRepay) {
            revert InsufficientTokenOut(address(ft), minFtOutToRepay, netFtOut);
        }
        (, uint128 debtAmt, , ) = gt.loanInfo(gtId);

        if (netFtOut > debtAmt) {
            uint remainningFt = netFtOut - debtAmt;
            ft.safeIncreaseAllowance(address(market), remainningFt);
            uint underlyingOut = market.sellFt(
                remainningFt.toUint128(),
                0,
                lsf
            );
            underlying.safeTransfer(receiver, underlyingOut);

            ft.safeIncreaseAllowance(address(gt), debtAmt);
            gt.repay(gtId, debtAmt, false);
        } else {
            ft.safeIncreaseAllowance(address(gt), netFtOut);
            gt.repay(gtId, netFtOut.toUint128(), false);
        }
        emit Repay(market, false, address(underlying), gtId, tokenInAmt);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
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

    /// @dev Market flash leverage flashloan callback
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
        bytes memory approvalData = abi.encodeCall(
            ISwapAdapter.approveOutputToken,
            (lastUnit.tokenOut, gt, collateralData)
        );
        _checkAdaper(lastUnit.adapter);
        (bool success, bytes memory returnData) = lastUnit.adapter.delegatecall(
            approvalData
        );
        if (!success) {
            revert ApproveTokenFailWhenSwap(lastUnit.tokenOut, returnData);
        }
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
        IERC20 repayToken,
        uint128 debtAmt,
        address,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external override ensureGtWhitelist(msg.sender) {
        (
            ITermMaxMarket market,
            address ft,
            SwapUnit[] memory units,
            uint32 lsf
        ) = abi.decode(
                callbackData,
                (ITermMaxMarket, address, SwapUnit[], uint32)
            );
        // do swap
        bytes memory outData = _doSwap(collateralData, units);

        if (address(repayToken) == ft) {
            IERC20 underlying = IERC20(units[units.length - 1].tokenOut);
            uint amount = abi.decode(outData, (uint));
            underlying.safeIncreaseAllowance(address(market), amount);
            market.buyFt(amount.toUint128(), debtAmt, lsf);
        }
        repayToken.safeIncreaseAllowance(msg.sender, debtAmt);
    }

    function _doSwap(
        bytes memory inputData,
        SwapUnit[] memory units
    ) internal returns (bytes memory outData) {
        for (uint i = 0; i < units.length; ++i) {
            _checkAdaper(units[i].adapter);
            // encode datas
            bytes memory dataToSwap = abi.encodeCall(
                ISwapAdapter.swap,
                (
                    units[i].tokenIn,
                    units[i].tokenOut,
                    inputData,
                    units[i].swapData
                )
            );

            // delegatecall
            (bool success, bytes memory returnData) = units[i]
                .adapter
                .delegatecall(dataToSwap);
            if (!success) {
                revert SwapFailed(units[i].adapter, returnData);
            }
            inputData = abi.decode(returnData, (bytes));
        }
        outData = inputData;
    }

    function _checkAdaper(address adapter) internal {
        if (!adapterWhitelist[adapter]) {
            revert AdapterNotWhitelisted(adapter);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
