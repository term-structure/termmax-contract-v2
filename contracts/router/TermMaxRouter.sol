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

import {ITermMaxTokenPair} from "../core/ITermMaxTokenPair.sol";
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

    /// @notice whitelist mapping of token pair
    mapping(address => bool) public tokenPairWhitelist;
    /// @notice whitelist mapping of market
    mapping(address => bool) public marketWhitelist;
    /// @notice whitelist mapping of dapter
    mapping(address => bool) public adapterWhitelist;

    /// @notice Check the token pair is whitelisted
    modifier ensureTokenPairWhitelist(address tokenPair) {
        if (!tokenPairWhitelist[tokenPair]) {
            revert MarketNotWhitelisted(tokenPair);
        }
        _;
    }
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

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

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
    function setTokenPairWhitelist(
        address tokenPair,
        bool isWhitelist
    ) external onlyOwner {
        tokenPairWhitelist[tokenPair] = isWhitelist;
        emit UpdateTokenPairWhiteList(tokenPair, isWhitelist);
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function setMarketWhitelist(
        address market,
        bool isWhitelist
    ) external onlyOwner {
        ITermMaxTokenPair tokenPair = ITermMaxMarket(market).tokenPair();

        if (!tokenPairWhitelist[address(tokenPair)]) {
            revert TOBEDEFINED();
        }

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
            IGearingToken gt,
            address collateral,
            IERC20 underlying
        ) = market.tokens();
        tokens[0] = ft;
        tokens[1] = xt;
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
        uint128 minFtOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netFtOut)
    {
        (IMintableERC20 ft, , , , IERC20 underlying) = market.tokens();

        _transferToSelfAndApproveSpender(
            underlying,
            msg.sender,
            address(market),
            tokenInAmt
        );
        (netFtOut) = market.buyFt(tokenInAmt, minFtOut);
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
        uint128 minTokenOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (IMintableERC20 ft, , , , IERC20 underlying) = market.tokens();

        _transferToSelfAndApproveSpender(
            ft,
            msg.sender,
            address(market),
            ftInAmt
        );

        (netTokenOut) = market.sellFt(ftInAmt, minTokenOut);
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
        uint128 minXtOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netXtOut)
    {
        (, IMintableERC20 xt, , , IERC20 underlying) = market.tokens();
        underlying.safeTransferFrom(msg.sender, address(this), tokenInAmt);

        underlying.safeIncreaseAllowance(address(market), tokenInAmt);
        (netXtOut) = market.buyXt(tokenInAmt, minXtOut);
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
        uint128 minTokenOut
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (, IMintableERC20 xt, , , IERC20 underlying) = market.tokens();
        xt.safeTransferFrom(msg.sender, address(this), xtInAmt);

        xt.safeIncreaseAllowance(address(market), xtInAmt);
        (netTokenOut) = market.sellXt(xtInAmt, minTokenOut);
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

    function _redeemFtAndXtToUnderlying(
        ITermMaxTokenPair tokenPair,
        address receiver,
        uint128 redeemAmt
    ) internal returns (uint256 underlyingAmtOut) {
        tokenPair.redeemFtAndXtToUnderlying(msg.sender, receiver, redeemAmt);
        underlyingAmtOut = redeemAmt;
    }

    /**
     * @inheritdoc ITermMaxRouter
     */
    function redeem(
        address receiver,
        ITermMaxTokenPair tokenPair,
        uint256 ftAmt,
        uint256 minCollOut,
        uint256 minTokenOut
    )
        external
        ensureTokenPairWhitelist(address(tokenPair))
        whenNotPaused
        returns (uint256 netCollOut, uint256 netTokenOut)
    {
        (
            IMintableERC20 ft,
            ,
            ,
            address collateralAddr,
            IERC20 underlying
        ) = tokenPair.tokens();
        if (ftAmt > 0) {
            _transferToSelfAndApproveSpender(
                IERC20(ft),
                msg.sender,
                address(tokenPair),
                ftAmt
            );
        }

        tokenPair.redeem(ftAmt);

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
            tokenPair,
            msg.sender,
            receiver,
            ftAmt,
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
        SwapUnit[] memory units
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 gtId, uint256 netXtOut)
    {
        ITermMaxTokenPair tokenPair = market.tokenPair();
        (
            ,
            IMintableERC20 xt,
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
            minXtAmt.toUint128()
        );
        bytes memory callbackData = abi.encode(address(gt), tokenInAmt, units);
        xt.safeIncreaseAllowance(address(market), netXtOut);
        gtId = tokenPair.leverageByXt(
            address(this),
            netXtOut.toUint128(),
            callbackData
        );
        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(uint128(maxLtv), ltv);
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
        ITermMaxTokenPair tokenPair = market.tokenPair();
        (
            ,
            IMintableERC20 xt,
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
        gtId = tokenPair.leverageByXt(
            address(this),
            xtInAmt.toUint128(),
            callbackData
        );
        gt.safeTransferFrom(address(this), receiver, gtId);

        (, , uint128 ltv, bytes memory collateralData) = gt.loanInfo(gtId);
        if (ltv > maxLtv) {
            revert LtvBiggerThanExpected(uint128(maxLtv), ltv);
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
        ITermMaxTokenPair tokenPair = market.tokenPair();
        /**
         * 1. MintGT with Collateral, and get GT, FT
         * 2. Sell FT to get UnderlyingToken
         * 3. Transfer UnderlyingToken and GT to Receiver
         */
        (uint256 gtId, uint128 netFtOut) = tokenPair.issueFt(
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
        (, , IGearingToken gt, , IERC20 underlying) = market.tokens();
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
        SwapUnit[] memory units
    )
        external
        ensureMarketWhitelist(address(market))
        whenNotPaused
        returns (uint256 netTokenOut)
    {
        (IMintableERC20 ft, , IGearingToken gt, , IERC20 underlying) = market.tokens();
        gt.safeTransferFrom(msg.sender, address(this), gtId, "");
        gt.flashRepay(gtId, byUnderlying, abi.encode(market, ft ,units));
        if(byUnderlying){
            // SafeTransfer remainning underlying token
            netTokenOut = underlying.balanceOf(address(this));
            underlying.safeTransfer(receiver, netTokenOut);
        }else{
            // Swap remainning ft to underlying token
            netTokenOut = ft.balanceOf(address(this));
            ft.safeIncreaseAllowance(address(market), netTokenOut);
            netTokenOut = market.sellFt(uint128(netTokenOut), 0);
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
        (IMintableERC20 ft, , IGearingToken gt, , ) = market.tokens();
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
        uint256 minFtOutToRepay
    ) external ensureMarketWhitelist(address(market)) whenNotPaused {
        (
            IMintableERC20 ft,
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
            minFtOutToRepay.toUint128()
        );
        if (netFtOut < minFtOutToRepay) {
            revert InsufficientTokenOut(address(ft), minFtOutToRepay, netFtOut);
        }
        (, uint128 debtAmt, , ) = gt.loanInfo(gtId);

        if (netFtOut > debtAmt) {
            uint remainningFt = netFtOut - debtAmt;
            ft.safeIncreaseAllowance(address(market), remainningFt);
            uint underlyingOut = market.sellFt(uint128(remainningFt), 0);
            underlying.safeTransfer(receiver, underlyingOut);

            ft.safeIncreaseAllowance(address(gt), debtAmt);
            gt.repay(gtId, debtAmt, false);
        }else{
            ft.safeIncreaseAllowance(address(gt), netFtOut);
            gt.repay(gtId, uint128(netFtOut), false);
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
        (, , IGearingToken gt, address collateral, ) = market.tokens();
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
        (ITermMaxMarket market, address ft, SwapUnit[] memory units) = 
            abi.decode(callbackData, (ITermMaxMarket, address, SwapUnit[]));
        // do swap
        bytes memory outData = _doSwap(collateralData, units);

        if(address(repayToken) == ft){
            IERC20 underlying = IERC20(units[units.length -1].tokenOut);
            uint amount = abi.decode(outData, (uint));
            underlying.safeIncreaseAllowance(address(market), amount);
            market.buyFt(uint128(amount), debtAmt);
        }
        repayToken.safeIncreaseAllowance(msg.sender, debtAmt);
    }

    function _doSwap(
        bytes memory inputData,
        SwapUnit[] memory units
    ) internal returns (bytes memory outData) {
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

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
