// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ITermMaxOrder, IERC20} from "../v1/ITermMaxOrder.sol";
import {ITermMaxMarket} from "../v1/ITermMaxMarket.sol";
import {IGearingToken} from "../v1/tokens/IGearingToken.sol";
import {Constants} from "../v1/lib/Constants.sol";
import {TermMaxCurve, MathLib} from "../v1/lib/TermMaxCurve.sol";
import {OrderErrors} from "../v1/errors/OrderErrors.sol";
import {OrderEvents} from "../v1/events/OrderEvents.sol";
import {OrderConfig, MarketConfig, CurveCuts, CurveCut, FeeConfig} from "../v1/storage/TermMaxStorage.sol";
import {ISwapCallback} from "../v1/ISwapCallback.sol";
import {TransferUtils} from "../v1/lib/TransferUtils.sol";
import {ITermMaxMarketV2} from "./ITermMaxMarketV2.sol";
import {ITermMaxOrderV2} from "./ITermMaxOrderV2.sol";
import {OrderEventsV2} from "./events/OrderEventsV2.sol";
import {OrderErrorsV2} from "./errors/OrderErrorsV2.sol";
import {StakingBuffer} from "./tokens/StakingBuffer.sol";

/**
 * @title TermMax Order V2 With Staking
 * @author Term Structure Labs
 */
contract TermMaxOrderV2WithStaking is
    ITermMaxOrder,
    ITermMaxOrderV2,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    OrderErrors,
    OrderEvents,
    StakingBuffer
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IERC4626;
    using MathLib for *;

    ITermMaxMarket public market;

    IERC20 private ft;
    IERC20 private xt;
    IERC20 private debtToken;
    IGearingToken private gt;

    OrderConfig private _orderConfig;

    uint64 private maturity;

    uint256 private _ftReserve;
    /// @notice The virtual xt reserve can present current price, which only changed when swap happens
    uint256 private _virtualXtReserve;
    IERC4626 public pool;
    uint256 private _totalStaked;

    /// @notice Check if the market is borrowing allowed
    modifier isBorrowingAllowed(OrderConfig memory config) {
        if (config.curveCuts.lendCurveCuts.length == 0) {
            revert BorrowIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier isLendingAllowed(OrderConfig memory config) {
        if (config.curveCuts.borrowCurveCuts.length == 0) {
            revert LendIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the order is tradable
    modifier isOpen() {
        _requireNotPaused();
        if (block.timestamp >= maturity) {
            revert TermIsNotOpen();
        }
        _;
    }

    modifier onlyMarket() {
        if (msg.sender != address(market)) revert OnlyMarket();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function maker() public view returns (address) {
        return owner();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function initialize(
        address,
        IERC20[3] memory,
        IGearingToken,
        uint256,
        ISwapCallback,
        CurveCuts memory,
        MarketConfig memory
    ) external virtual override initializer {
        revert OrderErrorsV2.UseOrderInitializationFunctionV2();
    }

    /**
     * @inheritdoc ITermMaxOrderV2
     */
    function initialize(
        address maker_,
        IERC20[3] memory tokens,
        IGearingToken gt_,
        OrderConfig memory orderConfig_,
        MarketConfig memory marketConfig
    ) external virtual override initializer {
        __Ownable_init(maker_);
        __ReentrancyGuard_init();
        __Pausable_init();
        market = ITermMaxMarket(_msgSender());
        _updateCurve(orderConfig_.curveCuts);

        _orderConfig.feeConfig = marketConfig.feeConfig;
        _orderConfig.maxXtReserve = orderConfig_.maxXtReserve;
        _orderConfig.swapTrigger = orderConfig_.swapTrigger;
        maturity = marketConfig.maturity;
        ft = tokens[0];
        xt = tokens[1];
        debtToken = tokens[2];
        gt = gt_;

        orderConfig_.feeConfig = marketConfig.feeConfig;
        emit OrderEventsV2.OrderInitialized(maker_, address(market), orderConfig_);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function orderConfig() external view virtual returns (OrderConfig memory) {
        return _orderConfig;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function tokenReserves() public view override returns (uint256, uint256) {
        return (ft.balanceOf(address(this)), xt.balanceOf(address(this)));
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function apr() external view virtual override returns (uint256 lendApr_, uint256 borrowApr_) {
        uint256 daysToMaturity = _daysToMaturity();
        uint256 oriXtReserve = xt.balanceOf(address(this));

        CurveCuts memory curveCuts = _orderConfig.curveCuts;
        if (curveCuts.lendCurveCuts.length == 0) {
            lendApr_ = 0;
        } else {
            uint256 lendCutId = TermMaxCurve.calcCutId(curveCuts.lendCurveCuts, oriXtReserve);
            (, uint256 lendVXtReserve, uint256 lendVFtReserve) = TermMaxCurve.calcIntervalProps(
                Constants.DECIMAL_BASE, daysToMaturity, curveCuts.lendCurveCuts[lendCutId], oriXtReserve
            );
            lendApr_ =
                ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / (lendVXtReserve * daysToMaturity));
        }
        if (curveCuts.borrowCurveCuts.length == 0) {
            borrowApr_ = type(uint256).max;
        } else {
            uint256 borrowCutId = TermMaxCurve.calcCutId(curveCuts.borrowCurveCuts, oriXtReserve);
            (, uint256 borrowVXtReserve, uint256 borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
                Constants.DECIMAL_BASE, daysToMaturity, curveCuts.borrowCurveCuts[borrowCutId], oriXtReserve
            );

            borrowApr_ = (
                (borrowVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR)
                    / (borrowVXtReserve * daysToMaturity)
            );
        }
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function updateOrder(OrderConfig memory newOrderConfig, int256 ftChangeAmt, int256 xtChangeAmt)
        external
        virtual
        override
        onlyOwner
    {
        _updateCurve(newOrderConfig.curveCuts);
        if (ftChangeAmt > 0) {
            ft.safeTransferFrom(msg.sender, address(this), ftChangeAmt.toUint256());
        } else if (ftChangeAmt < 0) {
            ft.safeTransfer(msg.sender, (-ftChangeAmt).toUint256());
        }
        if (xtChangeAmt > 0) {
            xt.safeTransferFrom(msg.sender, address(this), xtChangeAmt.toUint256());
        } else if (xtChangeAmt < 0) {
            xt.safeTransfer(msg.sender, (-xtChangeAmt).toUint256());
        }
        // Update the ft and xt reserve
        _ftReserve = ft.balanceOf(address(this));
        _virtualXtReserve = xt.balanceOf(address(this));
        _orderConfig.maxXtReserve = newOrderConfig.maxXtReserve;
        _orderConfig.gtId = newOrderConfig.gtId;
        _orderConfig.swapTrigger = newOrderConfig.swapTrigger;
        emit UpdateOrder(
            newOrderConfig.curveCuts,
            ftChangeAmt,
            xtChangeAmt,
            newOrderConfig.gtId,
            newOrderConfig.maxXtReserve,
            newOrderConfig.swapTrigger
        );
    }

    function _updateCurve(CurveCuts memory newCurveCuts) internal {
        if (newCurveCuts.lendCurveCuts.length > 0) {
            if (newCurveCuts.lendCurveCuts[0].liqSquare == 0 || newCurveCuts.lendCurveCuts[0].xtReserve != 0) {
                revert InvalidCurveCuts();
            }
        }
        for (uint256 i = 1; i < newCurveCuts.lendCurveCuts.length; i++) {
            if (
                newCurveCuts.lendCurveCuts[i].liqSquare == 0
                    || newCurveCuts.lendCurveCuts[i].xtReserve <= newCurveCuts.lendCurveCuts[i - 1].xtReserve
            ) {
                revert InvalidCurveCuts();
            }
            /*
                    R := (x' + beta') ^ 2 * DECIMAL_BASE / (x' + beta) ^ 2
                    L' ^ 2 := L ^ 2 * R / DECIMAL_BASE
                */
            if (
                newCurveCuts.lendCurveCuts[i].liqSquare
                    != (
                        newCurveCuts.lendCurveCuts[i - 1].liqSquare
                            * (
                                (
                                    (newCurveCuts.lendCurveCuts[i].xtReserve.plusInt256(newCurveCuts.lendCurveCuts[i].offset))
                                        ** 2 * Constants.DECIMAL_BASE
                                )
                                    / (
                                        newCurveCuts.lendCurveCuts[i].xtReserve.plusInt256(newCurveCuts.lendCurveCuts[i - 1].offset)
                                            ** 2
                                    )
                            )
                    ) / Constants.DECIMAL_BASE
            ) revert InvalidCurveCuts();
        }
        if (newCurveCuts.borrowCurveCuts.length > 0) {
            if (newCurveCuts.borrowCurveCuts[0].liqSquare == 0 || newCurveCuts.borrowCurveCuts[0].xtReserve != 0) {
                revert InvalidCurveCuts();
            }
        }
        for (uint256 i = 1; i < newCurveCuts.borrowCurveCuts.length; i++) {
            if (
                newCurveCuts.borrowCurveCuts[i].liqSquare == 0
                    || newCurveCuts.borrowCurveCuts[i].xtReserve <= newCurveCuts.borrowCurveCuts[i - 1].xtReserve
            ) {
                revert InvalidCurveCuts();
            }
            if (
                newCurveCuts.borrowCurveCuts[i].liqSquare
                    != (
                        newCurveCuts.borrowCurveCuts[i - 1].liqSquare
                            * (
                                (
                                    (
                                        newCurveCuts.borrowCurveCuts[i].xtReserve.plusInt256(
                                            newCurveCuts.borrowCurveCuts[i].offset
                                        )
                                    ) ** 2 * Constants.DECIMAL_BASE
                                )
                                    / (
                                        newCurveCuts.borrowCurveCuts[i].xtReserve.plusInt256(
                                            newCurveCuts.borrowCurveCuts[i - 1].offset
                                        ) ** 2
                                    )
                            )
                    ) / Constants.DECIMAL_BASE
            ) revert InvalidCurveCuts();
        }
        _orderConfig.curveCuts = newCurveCuts;
        emit OrderEventsV2.CurveUpdated(newCurveCuts);
    }

    function setCurve(CurveCuts memory newCurveCuts) external virtual onlyOwner {
        _updateCurve(newCurveCuts);
    }

    function _updateGeneralConfig(
        uint256 gtId,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger,
        uint256 virtualXtReserve
    ) internal {
        _orderConfig.gtId = gtId;
        _orderConfig.maxXtReserve = virtualXtReserve + maxXtReserve;
        _orderConfig.swapTrigger = swapTrigger;
        _virtualXtReserve = virtualXtReserve;
        emit OrderEventsV2.GeneralConfigUpdated(gtId, maxXtReserve, swapTrigger, virtualXtReserve);
    }

    function setGeneralConfig(uint256 gtId, uint256 maxXtReserve, ISwapCallback swapTrigger, uint256 virtualXtReserve)
        external
        virtual
        onlyOwner
    {
        _updateGeneralConfig(gtId, maxXtReserve, swapTrigger, virtualXtReserve);
    }

    function depositToPool(uint256 additionalAmount) external virtual onlyOwner {
        IERC20 _debtToken = debtToken;
        IERC4626 _pool = pool;
        if (additionalAmount != 0) {
            _debtToken.safeTransferFrom(msg.sender, address(this), additionalAmount);
        }
        // Burn ft and xt to debt token and deposit to pool
        uint256 ftBalance = ft.balanceOf(address(this));
        uint256 xtBalance = xt.balanceOf(address(this));
        uint256 debtTokenToMint = ftBalance > xtBalance ? ftBalance : xtBalance;
        debtTokenToMint += additionalAmount;
        market.burn(address(this), debtTokenToMint);
        debtToken.safeIncreaseAllowance(address(_pool), debtTokenToMint);
        _pool.deposit(debtTokenToMint, address(this));
    }

    function getRealReserves() external view virtual returns (uint256 ftReserve, uint256 xtReserve) {
        uint256 assetsInPool = _assetsInPool();
        ftReserve = ft.balanceOf(address(this)) + assetsInPool;
        xtReserve = xt.balanceOf(address(this)) + assetsInPool;
    }

    function _getFtReserve() internal view returns (uint256 ftBalance) {
        ftBalance = ft.balanceOf(address(this)) + _assetsInPool();
    }

    function _assetsInPool() internal view returns (uint256 assets) {
        if (pool != IERC4626(address(0))) {
            assets = pool.convertToAssets(pool.balanceOf(address(this)));
        }
    }

    function updateFeeConfig(FeeConfig memory newFeeConfig) external virtual override onlyMarket {
        _orderConfig.feeConfig = newFeeConfig;
        emit UpdateFeeConfig(newFeeConfig);
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity() internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtIn,
        uint128 minTokenOut,
        uint256 deadline
    ) external virtual override nonReentrant isOpen returns (uint256 netTokenOut) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        uint256 feeAmt;
        if (tokenAmtIn != 0) {
            IERC20 _debtToken = debtToken;
            IERC20 _ft = ft;
            IERC20 _xt = xt;

            if (tokenIn == _ft && tokenOut == _debtToken) {
                (netTokenOut, feeAmt) = _swapAndUpdateReserves(tokenAmtIn, minTokenOut, _sellFt);
            } else if (tokenIn == _xt && tokenOut == _debtToken) {
                (netTokenOut, feeAmt) = _swapAndUpdateReserves(tokenAmtIn, minTokenOut, _sellXt);
            } else if (tokenIn == _debtToken && tokenOut == _ft) {
                (netTokenOut, feeAmt) = _swapAndUpdateReserves(tokenAmtIn, minTokenOut, _buyFt);
            } else if (tokenIn == _debtToken && tokenOut == _xt) {
                (netTokenOut, feeAmt) = _swapAndUpdateReserves(tokenAmtIn, minTokenOut, _buyXt);
            } else {
                revert CantNotSwapToken(tokenIn, tokenOut);
            }

            // transfer token in
            tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);

            if (tokenOut == _debtToken) {
                _handleDebtTokenOutput(netTokenOut, feeAmt, recipient, _ft, _xt, _debtToken);
            } else {
                _handleFtXtOutput(tokenOut, netTokenOut, feeAmt, tokenAmtIn, recipient, _ft, _debtToken);
            }
        }

        emit SwapExactTokenToToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtIn, netTokenOut.toUint128(), feeAmt.toUint128()
        );
    }

    function _swapAndUpdateReserves(
        uint256 tokenAmtInOrOut,
        uint256 limitTokenAmt,
        function(
        uint256,
        uint256,
        OrderConfig memory) internal view returns (uint256, uint256, uint256, uint256, bool) func
    ) private returns (uint256, uint256) {
        OrderConfig memory orderConfig_ = _orderConfig;
        (uint256 netAmt, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(tokenAmtInOrOut, limitTokenAmt, orderConfig_);
        // check ft reserve and issue ft to self if needed
        uint256 newXtReserve = _virtualXtReserve;
        if (!isNegetiveXt) {
            uint256 ftReserve = _getFtReserve();
            if (ftReserve < deltaFt) {
                _issueFtToSelf(deltaFt - ftReserve, orderConfig_);
            }
            // check xt reserve
            newXtReserve += deltaXt;
            if (newXtReserve > orderConfig_.maxXtReserve) {
                revert XtReserveTooHigh();
            }
        } else {
            newXtReserve -= deltaXt;
        }
        _virtualXtReserve = newXtReserve;

        /// @dev callback the changes of ft and xt reserve to trigger
        _triggerSwapCallback(deltaFt, deltaXt, isNegetiveXt);
        return (netAmt, feeAmt);
    }

    function _handleDebtTokenOutput(
        uint256 netTokenOut,
        uint256 feeAmt,
        address recipient,
        IERC20 _ft,
        IERC20 _xt,
        IERC20 _debtToken
    ) private {
        uint256 ftBalance = _ft.balanceOf(address(this));
        uint256 xtBalance = _xt.balanceOf(address(this));
        uint256 tokenToMint = netTokenOut + feeAmt;

        if (tokenToMint > ftBalance || netTokenOut > xtBalance) {
            uint256 mintAmount = _calculateMintAmount(tokenToMint, netTokenOut, ftBalance, xtBalance);
            _withdrawWithBuffer(address(_debtToken), address(this), mintAmount);
            _debtToken.safeIncreaseAllowance(address(market), mintAmount);
            market.mint(address(this), mintAmount);
        }

        market.burn(recipient, netTokenOut);
        _ft.safeTransfer(market.config().treasurer, feeAmt);
    }

    function _handleFtXtOutput(
        IERC20 tokenOut,
        uint256 netTokenOut,
        uint256 feeAmt,
        uint256 tokenAmtIn,
        address recipient,
        IERC20 _ft,
        IERC20 _debtToken
    ) private {
        // Mint debt token to ft and xt
        _debtToken.safeIncreaseAllowance(address(market), tokenAmtIn);
        market.mint(address(this), tokenAmtIn);

        // Pay fee
        _ft.safeTransfer(market.config().treasurer, feeAmt);

        // Check if we need to withdraw additional tokens
        uint256 availableBalance = tokenOut.balanceOf(address(this));
        if (availableBalance < netTokenOut) {
            uint256 tokenToWithdraw = netTokenOut - availableBalance;
            _withdrawWithBuffer(address(tokenOut), address(this), tokenToWithdraw);
            _debtToken.safeIncreaseAllowance(address(market), tokenToWithdraw);
            market.mint(address(this), tokenToWithdraw);
        }

        tokenOut.safeTransfer(recipient, netTokenOut);
    }

    function _calculateMintAmount(uint256 tokenToMint, uint256 netTokenOut, uint256 ftBalance, uint256 xtBalance)
        private
        pure
        returns (uint256)
    {
        uint256 mintAmount = tokenToMint - ftBalance;
        uint256 xtShortfall = netTokenOut > xtBalance ? netTokenOut - xtBalance : 0;
        return mintAmount > xtShortfall ? mintAmount : xtShortfall;
    }

    function _triggerSwapCallback(uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) private {
        if (address(_orderConfig.swapTrigger) != address(0)) {
            if (isNegetiveXt) {
                _orderConfig.swapTrigger.afterSwap(
                    _ftReserve, _virtualXtReserve, deltaFt.toInt256(), -deltaXt.toInt256()
                );
            } else {
                _orderConfig.swapTrigger.afterSwap(
                    _ftReserve, _virtualXtReserve, -deltaFt.toInt256(), deltaXt.toInt256()
                );
            }
        }
    }

    function _buyFt(uint256 debtTokenAmtIn, uint256 minTokenOut, OrderConfig memory config)
        internal
        view
        isLendingAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _buyToken(debtTokenAmtIn, minTokenOut, config, _buyFtStep);
    }

    function _buyXt(uint256 debtTokenAmtIn, uint256 minTokenOut, OrderConfig memory config)
        internal
        view
        isBorrowingAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _buyToken(debtTokenAmtIn, minTokenOut, config, _buyXtStep);
    }

    function _sellFt(uint256 ftAmtIn, uint256 minDebtTokenOut, OrderConfig memory config)
        internal
        view
        isBorrowingAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _sellToken(ftAmtIn, minDebtTokenOut, config, _sellFtStep);
    }

    function _sellXt(uint256 xtAmtIn, uint256 minDebtTokenOut, OrderConfig memory config)
        internal
        view
        isLendingAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _sellToken(xtAmtIn, minDebtTokenOut, config, _sellXtStep);
    }

    function _buyToken(
        uint256 debtTokenAmtIn,
        uint256 minTokenOut,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal view returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            func(_daysToMaturity(), _virtualXtReserve, debtTokenAmtIn, config);

        netOut += debtTokenAmtIn;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        // if (func == ft) {
        //     uint256 ftIssued = _issueFtToSelf(oriFtReserve + debtTokenAmtIn, netOut + feeAmt, config);
        //     if (ftIssued > 0) {
        //         deltaFt = isNegetiveXt ? deltaFt + ftIssued : deltaFt - ftIssued;
        //     }
        // }

        return (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    function _buyFtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 debtTokenAmtIn, OrderConfig memory config)
        internal
        view
        returns (uint256 tokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, tokenAmtOut) = TermMaxCurve.buyFt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = (tokenAmtOut * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif - tokenAmtOut;

        // ft reserve decrease, xt reserve increase
        deltaFt = tokenAmtOut + feeAmt;
        isNegetiveXt = false;
    }

    function _buyXtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 debtTokenAmtIn, OrderConfig memory config)
        internal
        view
        returns (uint256 tokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);
        (tokenAmtOut, deltaFt) = TermMaxCurve.buyXt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        deltaXt = tokenAmtOut;
        isNegetiveXt = true;
    }

    function _sellToken(
        uint256 tokenAmtIn,
        uint256 minDebtTokenOut,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal view returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256, uint256, uint256, uint256, bool) {
        (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(_daysToMaturity(), _virtualXtReserve, tokenAmtIn, config);
        if (netOut < minDebtTokenOut) revert UnexpectedAmount(minDebtTokenOut, netOut);
        // if (tokenIn == xt) {
        //     uint256 ftIssued = _issueFtToSelf(oriFtReserve, netOut + feeAmt, config);
        //     if (ftIssued > 0) {
        //         // if xt is negative, we need to increase ft reserve
        //         deltaFt = isNegetiveXt ? deltaFt + ftIssued : deltaFt - ftIssued;
        //     }
        // }
        return (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    function _sellFtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 tokenAmtIn, OrderConfig memory config)
        internal
        view
        returns (uint256 debtTokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);
        (debtTokenAmtOut, deltaFt) = TermMaxCurve.sellFt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        deltaXt = debtTokenAmtOut;
        isNegetiveXt = true;
    }

    function _sellXtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 tokenAmtIn, OrderConfig memory config)
        internal
        view
        returns (uint256 debtTokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, debtTokenAmtOut) = TermMaxCurve.sellXt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = (debtTokenAmtOut * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif
            - debtTokenAmtOut;

        // ft reserve decrease, xt reserve increase
        deltaFt = debtTokenAmtOut + feeAmt;
        isNegetiveXt = false;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtOut,
        uint128 maxTokenIn,
        uint256 deadline
    ) external virtual override nonReentrant isOpen returns (uint256 netTokenIn) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        uint256 feeAmt;
        if (tokenAmtOut != 0 && maxTokenIn != 0) {
            IERC20 _debtToken = debtToken;
            IERC20 _ft = ft;
            IERC20 _xt = xt;
            if (tokenIn == _debtToken && tokenOut == _ft) {
                (netTokenIn, feeAmt) = _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, _buyExactFt);
            } else if (tokenIn == _debtToken && tokenOut == _xt) {
                (netTokenIn, feeAmt) = _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, _buyExactXt);
            } else if (tokenIn == _ft && tokenOut == _debtToken) {
                (netTokenIn, feeAmt) = _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, _sellFtForExactToken);
            } else if (tokenIn == _xt && tokenOut == _debtToken) {
                (netTokenIn, feeAmt) = _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, _sellXtForExactToken);
            } else {
                revert CantNotSwapToken(tokenIn, tokenOut);
            }
            // transfer token in
            tokenIn.safeTransferFrom(msg.sender, address(this), netTokenIn);

            if (tokenOut == _debtToken) {
                _handleDebtTokenOutput(tokenAmtOut, feeAmt, recipient, _ft, _xt, _debtToken);
            } else {
                _handleFtXtOutput(tokenOut, tokenAmtOut, feeAmt, netTokenIn, recipient, _ft, _debtToken);
            }
        }

        emit SwapTokenToExactToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtOut, netTokenIn.toUint128(), feeAmt.toUint128()
        );
    }

    function _buyExactFt(uint256 tokenAmtOut, uint256 maxTokenIn, OrderConfig memory config)
        internal
        view
        isLendingAllowed(config)
        returns (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _buyExactToken(tokenAmtOut, maxTokenIn, config, _buyExactFtStep);
    }

    function _buyExactXt(uint256 tokenAmtOut, uint256 maxTokenIn, OrderConfig memory config)
        internal
        view
        isBorrowingAllowed(config)
        returns (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _buyExactToken(tokenAmtOut, maxTokenIn, config, _buyExactXtStep);
    }

    function _buyExactToken(
        uint256 tokenAmtOut,
        uint256 maxTokenIn,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal view returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256, uint256, uint256, uint256, bool) {
        (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(_daysToMaturity(), _virtualXtReserve, tokenAmtOut, config);

        if (netTokenIn > maxTokenIn) revert UnexpectedAmount(maxTokenIn, netTokenIn);

        // if (tokenOut == ft) {
        //     uint256 ftIssued = _issueFtToSelf(oriFtReserve + netTokenIn, tokenAmtOut + feeAmt, config);
        //     if (ftIssued > 0) {
        //         deltaFt = isNegetiveXt ? deltaFt + ftIssued : deltaFt - ftIssued;
        //     }
        // }

        return (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    function _buyExactFtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 ftAmtOut, OrderConfig memory config)
        internal
        view
        returns (uint256 debtTokenAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, deltaFt) = TermMaxCurve.buyExactFt(nif, daysToMaturity, cuts, oriXtReserve, ftAmtOut);
        debtTokenAmtIn = deltaXt;
        feeAmt = (deltaFt * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif - deltaFt;

        // ft reserve decrease, xt reserve increase
        deltaFt += feeAmt;
        isNegetiveXt = false;
    }

    function _buyExactXtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 xtAmtOut, OrderConfig memory config)
        internal
        view
        returns (uint256 debtTokenAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);
        (deltaXt, deltaFt) = TermMaxCurve.buyExactXt(nif, daysToMaturity, cuts, oriXtReserve, xtAmtOut);
        debtTokenAmtIn = deltaFt;
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        isNegetiveXt = true;
    }

    function _sellFtForExactToken(uint256 debtTokenAmtOut, uint256 maxFtIn, OrderConfig memory config)
        internal
        view
        isBorrowingAllowed(config)
        returns (uint256 netIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _sellTokenForExactToken(debtTokenAmtOut, maxFtIn, config, _sellFtForExactTokenStep);
    }

    function _sellXtForExactToken(uint256 debtTokenAmtOut, uint256 maxXtIn, OrderConfig memory config)
        internal
        view
        isLendingAllowed(config)
        returns (uint256 netIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _sellTokenForExactToken(debtTokenAmtOut, maxXtIn, config, _sellXtForExactTokenStep);
    }

    function _sellTokenForExactToken(
        uint256 debtTokenAmtOut,
        uint256 maxTokenIn,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal view returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256, uint256, uint256, uint256, bool) {
        (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(_daysToMaturity(), _virtualXtReserve, debtTokenAmtOut, config);

        if (netTokenIn > maxTokenIn) revert UnexpectedAmount(maxTokenIn, netTokenIn);

        // if (tokenIn == xt) {
        //     uint256 ftIssued = _issueFtToSelf(oriFtReserve, debtTokenAmtOut + feeAmt, config);
        //     if (ftIssued > 0) {
        //         // if xt is negative, we need to increase ft reserve
        //         deltaFt = isNegetiveXt ? deltaFt + ftIssued : deltaFt - ftIssued;
        //     }
        // }
        return (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    function _sellFtForExactTokenStep(
        uint256 daysToMaturity,
        uint256 oriXtReserve,
        uint256 debtTokenOut,
        OrderConfig memory config
    ) internal view returns (uint256 ftAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);

        (deltaXt, deltaFt) = TermMaxCurve.sellFtForExactDebtToken(nif, daysToMaturity, cuts, oriXtReserve, debtTokenOut);
        ftAmtIn = deltaFt + debtTokenOut;

        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        deltaXt = debtTokenOut;
        isNegetiveXt = true;
    }

    function _sellXtForExactTokenStep(
        uint256 daysToMaturity,
        uint256 oriXtReserve,
        uint256 debtTokenOut,
        OrderConfig memory config
    ) internal view returns (uint256 xtAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, deltaFt) = TermMaxCurve.sellXtForExactDebtToken(nif, daysToMaturity, cuts, oriXtReserve, debtTokenOut);
        xtAmtIn = deltaXt + debtTokenOut;

        feeAmt = (deltaFt * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif - deltaFt;

        // ft reserve decrease, xt reserve increase
        deltaFt += feeAmt;
        deltaXt = debtTokenOut;
        isNegetiveXt = false;
    }

    /**
     * @notice Issue ft by existed gt.
     * @notice This fuction will be triggered when ft reserve can not cover the output amount.
     */
    function _issueFtToSelf(uint256 amount, OrderConfig memory config) internal {
        if (config.gtId == 0) revert CantNotIssueFtWithoutGt();
        uint256 debtAmtToIssue = (amount * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - market.mintGtFeeRatio());
        market.issueFtByExistedGt(address(this), (debtAmtToIssue).toUint128(), config.gtId);
    }

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external virtual onlyOwner {
        if (token == debtToken) {
            ITermMaxMarketV2(address(market)).burn(address(this), recipient, amount);
        } else {
            token.safeTransfer(recipient, amount);
        }
        // Update the ft and xt reserve
        _ftReserve = ft.balanceOf(address(this)) + _totalStaked;
        _virtualXtReserve = xt.balanceOf(address(this)) + _totalStaked;
        emit WithdrawAssets(token, _msgSender(), recipient, amount);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function pause() external virtual override onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function unpause() external virtual override onlyOwner {
        _unpause();
    }

    function _bufferConfig(address assetAddr) internal view virtual override returns (BufferConfig memory) {}

    function _depositToPool(address assetAddr, uint256 amount) internal virtual override {
        IERC4626 _pool = pool;
        if (address(_pool) != address(0)) {
            _totalStaked += amount;
            market.burn(address(this), amount);
            IERC20(assetAddr).safeIncreaseAllowance(address(_pool), amount);
            _pool.deposit(amount, address(this));
        }
    }

    function _withdrawFromPool(address, address to, uint256 amount) internal virtual override {
        IERC4626 _pool = pool;
        if (address(_pool) != address(0)) {
            _totalStaked = _totalStaked < amount ? 0 : _totalStaked - amount;
            _pool.withdraw(amount, address(this), to);
        }
    }

    function _assetInPool(address) internal view virtual override returns (uint256 amount) {
        return _totalStaked;
    }

    function redeemAll(address recipient) external virtual onlyOwner returns (uint256 badDebt) {
        IERC4626 _pool = pool;
        if (address(_pool) != address(0)) {
            uint256 shares = _pool.balanceOf(address(this));
            _pool.safeTransfer(recipient, shares);
        }
        uint256 ftBalance = ft.balanceOf(address(this));
        if (ftBalance != 0) {
            _ftReserve = 0;
            (uint256 finalReceived,) = market.redeem(ftBalance, recipient);
            badDebt = ftBalance - finalReceived;
        }
        market.burn(recipient, ftBalance);
        uint256 debtBalance = debtToken.balanceOf(address(this));
        debtToken.safeTransfer(recipient, debtBalance);

        _totalStaked = 0;
    }
}
