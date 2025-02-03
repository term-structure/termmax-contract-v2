// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable, Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxOrder, IERC20} from "./ITermMaxOrder.sol";
import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {Constants} from "./lib/Constants.sol";
import {TermMaxCurve, MathLib} from "./lib/TermMaxCurve.sol";
import {OrderErrors} from "./errors/OrderErrors.sol";
import {OrderEvents} from "./events/OrderEvents.sol";
import {OrderConfig, MarketConfig, CurveCuts, CurveCut, FeeConfig} from "./storage/TermMaxStorage.sol";
import {ISwapCallback} from "./ISwapCallback.sol";
import {TransferUtils} from "./lib/TransferUtils.sol";

/**
 * @title TermMax Order
 * @author Term Structure Labs
 */
contract TermMaxOrder is
    ITermMaxOrder,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    OrderErrors,
    OrderEvents
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;

    ITermMaxMarket public market;

    IERC20 private ft;
    IERC20 private xt;
    IERC20 private debtToken;
    IGearingToken private gt;

    OrderConfig private _orderConfig;

    uint64 private maturity;

    uint256 private constant T_FT_RESERVE_STORE = 0;
    uint256 private constant T_XT_RESERVE_STORE = 1;

    function setTransientFtReserve(uint ftReserve) private {
        assembly {
            tstore(T_FT_RESERVE_STORE, ftReserve)
        }
    }

    function setTransientXtReserve(uint xtReserve) private {
        assembly {
            tstore(T_XT_RESERVE_STORE, xtReserve)
        }
    }

    function getTransientFtReserve() private view returns (uint ftReserve) {
        assembly {
            ftReserve := tload(T_FT_RESERVE_STORE)
        }
    }

    function getTransientXtReserve() private view returns (uint xtReserve) {
        assembly {
            xtReserve := tload(T_XT_RESERVE_STORE)
        }
    }

    /// @notice Check if the market is borrowing allowed
    modifier isBorrowingAllowed(OrderConfig memory config) {
        if (config.curveCuts.borrowCurveCuts.length == 0) {
            revert BorrowIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier isLendingAllowed(OrderConfig memory config) {
        if (config.curveCuts.lendCurveCuts.length == 0) {
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
        address maker_,
        IERC20[3] memory tokens,
        IGearingToken gt_,
        uint256 maxXtReserve_,
        ISwapCallback swapTrigger,
        CurveCuts memory curveCuts_,
        MarketConfig memory marketConfig
    ) external override initializer {
        __Ownable_init(maker_);
        __ReentrancyGuard_init();
        __Pausable_init();
        market = ITermMaxMarket(_msgSender());

        // _orderConfig.curveCuts = curveCuts_;
        _updateCurve(curveCuts_);
        _orderConfig.feeConfig = marketConfig.feeConfig;
        _orderConfig.maxXtReserve = maxXtReserve_;
        _orderConfig.swapTrigger = swapTrigger;
        maturity = marketConfig.maturity;

        ft = tokens[0];
        xt = tokens[1];
        debtToken = tokens[2];
        gt = gt_;
        emit OrderInitialized(market, maker_, maxXtReserve_, swapTrigger, curveCuts_);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function orderConfig() external view returns (OrderConfig memory) {
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
    function apr() external view override returns (uint256 lendApr_, uint256 borrowApr_) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = xt.balanceOf(address(this));

        CurveCuts memory curveCuts = _orderConfig.curveCuts;

        uint lendCutId = TermMaxCurve.calcCutId(curveCuts.lendCurveCuts, oriXtReserve);
        (, uint lendVXtReserve, uint lendVFtReserve) = TermMaxCurve.calcIntervalProps(
            Constants.DECIMAL_BASE,
            daysToMaturity,
            curveCuts.lendCurveCuts[lendCutId],
            oriXtReserve
        );
        lendApr_ = ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) /
            (lendVXtReserve * daysToMaturity));

        uint borrowCutId = TermMaxCurve.calcCutId(curveCuts.borrowCurveCuts, oriXtReserve);
        (, uint borrowVXtReserve, uint borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
            Constants.DECIMAL_BASE,
            daysToMaturity,
            curveCuts.borrowCurveCuts[borrowCutId],
            oriXtReserve
        );
        borrowApr_ = ((borrowVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) /
            (borrowVXtReserve * daysToMaturity));
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function updateOrder(
        OrderConfig memory newOrderConfig,
        int256 ftChangeAmt,
        int256 xtChangeAmt
    ) external override onlyOwner {
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
        _orderConfig.maxXtReserve = newOrderConfig.maxXtReserve;
        // check gtId
        if (newOrderConfig.gtId != 0 && address(this) != gt.getApproved(newOrderConfig.gtId)) {
            revert GtNotApproved(newOrderConfig.gtId);
        }
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
        bytes32 newCurveCutsHash = keccak256(abi.encode(newCurveCuts));
        CurveCuts memory oldCurveCuts = _orderConfig.curveCuts;
        if (keccak256(abi.encode(oldCurveCuts)) != newCurveCutsHash) {
            if (newCurveCuts.lendCurveCuts.length > 0) {
                if (newCurveCuts.lendCurveCuts[0].xtReserve != 0) revert InvalidCurveCuts();
            }
            for (uint i = 1; i < newCurveCuts.lendCurveCuts.length; i++) {
                if (newCurveCuts.lendCurveCuts[i].xtReserve <= newCurveCuts.lendCurveCuts[i - 1].xtReserve)
                    revert InvalidCurveCuts();
                if (
                    newCurveCuts.lendCurveCuts[i].offset !=
                    ((newCurveCuts.lendCurveCuts[i].xtReserve + newCurveCuts.lendCurveCuts[i - 1].offset) *
                        MathLib.sqrt(
                            (newCurveCuts.lendCurveCuts[i].liqSquare * Constants.DECIMAL_BASE_SQ) /
                                newCurveCuts.lendCurveCuts[i - 1].liqSquare
                        )) /
                        Constants.DECIMAL_BASE -
                        newCurveCuts.lendCurveCuts[i].xtReserve
                ) revert InvalidCurveCuts();
            }
            if (newCurveCuts.borrowCurveCuts.length > 0) {
                if (newCurveCuts.borrowCurveCuts[0].xtReserve != 0) revert InvalidCurveCuts();
            }
            for (uint i = 1; i < newCurveCuts.borrowCurveCuts.length; i++) {
                if (newCurveCuts.borrowCurveCuts[i].xtReserve <= newCurveCuts.borrowCurveCuts[i - 1].xtReserve)
                    revert InvalidCurveCuts();
                if (
                    newCurveCuts.borrowCurveCuts[i].offset !=
                    ((newCurveCuts.borrowCurveCuts[i].xtReserve + newCurveCuts.borrowCurveCuts[i - 1].offset) *
                        MathLib.sqrt(
                            (newCurveCuts.borrowCurveCuts[i].liqSquare * Constants.DECIMAL_BASE_SQ) /
                                newCurveCuts.borrowCurveCuts[i - 1].liqSquare
                        )) /
                        Constants.DECIMAL_BASE -
                        newCurveCuts.borrowCurveCuts[i].xtReserve
                ) revert InvalidCurveCuts();
            }
            _orderConfig.curveCuts = newCurveCuts;
        }
    }

    function updateFeeConfig(FeeConfig memory newFeeConfig) external override onlyMarket {
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
        uint128 minTokenOut
    ) external override nonReentrant isOpen returns (uint256 netTokenOut) {
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        OrderConfig memory config = _orderConfig;
        uint feeAmt;
        setTransientFtReserve(ft.balanceOf(address(this)));
        setTransientXtReserve(xt.balanceOf(address(this)));
        if (tokenIn == ft && tokenOut == debtToken) {
            (netTokenOut, feeAmt) = _sellFt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == xt && tokenOut == debtToken) {
            (netTokenOut, feeAmt) = _sellXt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == debtToken && tokenOut == ft) {
            (netTokenOut, feeAmt) = _buyFt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == debtToken && tokenOut == xt) {
            (netTokenOut, feeAmt) = _buyXt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else {
            revert CantNotSwapToken(tokenIn, tokenOut);
        }

        ft.safeTransfer(market.config().treasurer, feeAmt);

        if (address(_orderConfig.swapTrigger) != address(0)) {
            int256 deltaFt = ft.balanceOf(address(this)).toInt256() - getTransientFtReserve().toInt256();
            int256 deltaXt = xt.balanceOf(address(this)).toInt256() - getTransientXtReserve().toInt256();
            _orderConfig.swapTrigger.swapCallback(deltaFt, deltaXt);
        }
        emit SwapExactTokenToToken(
            tokenIn,
            tokenOut,
            msg.sender,
            recipient,
            tokenAmtIn,
            netTokenOut.toUint128(),
            feeAmt.toUint128()
        );
    }

    function _buyFt(
        uint debtTokenAmtIn,
        uint minTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isLendingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        (netOut, feeAmt) = _buyToken(caller, recipient, debtTokenAmtIn, minTokenOut, config, _buyFtStep);
        if (xt.balanceOf(address(this)) > config.maxXtReserve) {
            revert XtReserveTooHigh();
        }
    }

    function _buyXt(
        uint debtTokenAmtIn,
        uint minTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isBorrowingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        (netOut, feeAmt) = _buyToken(caller, recipient, debtTokenAmtIn, minTokenOut, config, _buyXtStep);
    }

    function _sellFt(
        uint ftAmtIn,
        uint minDebtTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isBorrowingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        (netOut, feeAmt) = _sellToken(caller, recipient, ftAmtIn, minDebtTokenOut, config, _sellFtStep);
    }

    function _sellXt(
        uint xtAmtIn,
        uint minDebtTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isLendingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        (netOut, feeAmt) = _sellToken(caller, recipient, xtAmtIn, minDebtTokenOut, config, _sellXtStep);
        if (xt.balanceOf(address(this)) > config.maxXtReserve) {
            revert XtReserveTooHigh();
        }
    }

    function _buyToken(
        address caller,
        address recipient,
        uint debtTokenAmtIn,
        uint minTokenOut,
        OrderConfig memory config,
        function(uint, uint, uint, OrderConfig memory) internal view returns (uint, uint, IERC20) func
    ) internal returns (uint256, uint256) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = getTransientXtReserve();

        (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) = func(daysToMaturity, oriXtReserve, debtTokenAmtIn, config);

        uint256 netOut = tokenAmtOut + debtTokenAmtIn;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        debtToken.safeTransferFrom(caller, address(this), debtTokenAmtIn);

        debtToken.safeIncreaseAllowance(address(market), debtTokenAmtIn);
        market.mint(address(this), debtTokenAmtIn);
        if (tokenOut == ft) {
            uint ftReserve = getTransientFtReserve();
            if (ftReserve < netOut + feeAmt) _issueFt(address(this), ftReserve, netOut + feeAmt, config);
        }

        tokenOut.safeTransfer(recipient, netOut);

        return (netOut, feeAmt);
    }

    function _buyFtStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint nif = Constants.DECIMAL_BASE - uint(feeConfig.lendTakerFeeRatio);
        (, tokenAmtOut) = TermMaxCurve.buyFt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = (tokenAmtOut * (Constants.DECIMAL_BASE + uint(feeConfig.borrowMakerFeeRatio))) / nif - tokenAmtOut;
        tokenOut = ft;
    }

    function _buyXtStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint nif = Constants.DECIMAL_BASE + uint(feeConfig.borrowTakerFeeRatio);
        uint deltaFt;
        (tokenAmtOut, deltaFt) = TermMaxCurve.buyXt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint(feeConfig.lendMakerFeeRatio))) / nif;
        tokenOut = xt;
    }

    function _sellToken(
        address caller,
        address recipient,
        uint tokenAmtIn,
        uint minDebtTokenOut,
        OrderConfig memory config,
        function(uint, uint, uint, OrderConfig memory) internal view returns (uint, uint, IERC20) func
    ) internal returns (uint256, uint256) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = getTransientXtReserve();

        (uint netOut, uint feeAmt, IERC20 tokenIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn, config);
        if (netOut < minDebtTokenOut) revert UnexpectedAmount(minDebtTokenOut, netOut);

        tokenIn.safeTransferFrom(caller, address(this), tokenAmtIn);
        if (tokenIn == xt) {
            uint ftReserve = getTransientFtReserve();
            if (ftReserve < netOut) _issueFt(recipient, ftReserve, netOut + feeAmt, config);
        }
        ft.approve(address(market), netOut);
        xt.approve(address(market), netOut);
        market.burn(recipient, netOut);
        return (netOut, feeAmt);
    }

    function _sellFtStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint nif = Constants.DECIMAL_BASE + uint(feeConfig.borrowTakerFeeRatio);
        uint deltaFt;
        (debtTokenAmtOut, deltaFt) = TermMaxCurve.sellFt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint(feeConfig.lendMakerFeeRatio))) / nif;
        tokenIn = ft;
    }

    function _sellXtStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint nif = Constants.DECIMAL_BASE - uint(feeConfig.lendTakerFeeRatio);
        (, debtTokenAmtOut) = TermMaxCurve.sellXt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt =
            (debtTokenAmtOut * (Constants.DECIMAL_BASE + uint(feeConfig.borrowMakerFeeRatio))) /
            nif -
            debtTokenAmtOut;
        tokenIn = xt;
    }

    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtOut,
        uint128 maxTokenIn
    ) external nonReentrant isOpen returns (uint256 netTokenIn) {
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        OrderConfig memory config = _orderConfig;
        uint feeAmt;
        setTransientFtReserve(ft.balanceOf(address(this)));
        setTransientXtReserve(xt.balanceOf(address(this)));
        if (tokenIn == debtToken && tokenOut == ft) {
            (netTokenIn, feeAmt) = _buyExactFt(tokenAmtOut, maxTokenIn, msg.sender, recipient, config);
        } else if (tokenIn == debtToken && tokenOut == xt) {
            (netTokenIn, feeAmt) = _buyExactXt(tokenAmtOut, maxTokenIn, msg.sender, recipient, config);
        } else if (tokenIn == ft && tokenOut == debtToken) {
            (netTokenIn, feeAmt) = _sellFtForExactToken(tokenAmtOut, maxTokenIn, msg.sender, recipient, config);
        } else if (tokenIn == xt && tokenOut == debtToken) {
            (netTokenIn, feeAmt) = _sellXtForExactToken(tokenAmtOut, maxTokenIn, msg.sender, recipient, config);
        } else {
            revert CantNotSwapToken(tokenIn, tokenOut);
        }
        ft.safeTransfer(market.config().treasurer, feeAmt);

        if (address(_orderConfig.swapTrigger) != address(0)) {
            int256 deltaFt = ft.balanceOf(address(this)).toInt256() - getTransientFtReserve().toInt256();
            int256 deltaXt = xt.balanceOf(address(this)).toInt256() - getTransientXtReserve().toInt256();
            _orderConfig.swapTrigger.swapCallback(deltaFt, deltaXt);
        }
        emit SwapTokenToExactToken(
            tokenIn,
            tokenOut,
            msg.sender,
            recipient,
            tokenAmtOut,
            netTokenIn.toUint128(),
            feeAmt.toUint128()
        );
    }

    function _buyExactFt(
        uint tokenAmtOut,
        uint maxTokenIn,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isLendingAllowed(config) returns (uint256 netTokenIn, uint256 feeAmt) {
        (netTokenIn, feeAmt) = _buyExactToken(caller, recipient, tokenAmtOut, maxTokenIn, config, _buyExactFtStep);
        if (xt.balanceOf(address(this)) > config.maxXtReserve) {
            revert XtReserveTooHigh();
        }
    }

    function _buyExactXt(
        uint tokenAmtOut,
        uint maxTokenIn,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isBorrowingAllowed(config) returns (uint256 netTokenIn, uint256 feeAmt) {
        (netTokenIn, feeAmt) = _buyExactToken(caller, recipient, tokenAmtOut, maxTokenIn, config, _buyExactXtStep);
    }

    function _buyExactToken(
        address caller,
        address recipient,
        uint tokenAmtOut,
        uint maxTokenIn,
        OrderConfig memory config,
        function(uint, uint, uint, OrderConfig memory) internal view returns (uint, uint, IERC20) func
    ) internal returns (uint256, uint256) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = getTransientXtReserve();

        (uint netTokenIn, uint feeAmt, IERC20 tokenOut) = func(daysToMaturity, oriXtReserve, tokenAmtOut, config);

        if (netTokenIn > maxTokenIn) revert UnexpectedAmount(maxTokenIn, netTokenIn);

        debtToken.safeTransferFrom(caller, address(this), netTokenIn);

        debtToken.safeIncreaseAllowance(address(market), netTokenIn);
        market.mint(address(this), netTokenIn);
        if (tokenOut == ft) {
            uint ftReserve = getTransientFtReserve();
            if (ftReserve < tokenAmtOut + feeAmt) _issueFt(address(this), ftReserve, tokenAmtOut + feeAmt, config);
        }

        tokenOut.safeTransfer(recipient, tokenAmtOut);

        return (netTokenIn, feeAmt);
    }

    function _buyExactFtStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint ftAmtOut,
        OrderConfig memory config
    ) internal view returns (uint debtTokenAmtIn, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint nif = Constants.DECIMAL_BASE - uint(feeConfig.lendTakerFeeRatio);
        (uint deltaXt, uint negDeltaFt) = TermMaxCurve.buyExactFt(nif, daysToMaturity, cuts, oriXtReserve, ftAmtOut);
        debtTokenAmtIn = deltaXt;
        feeAmt = (negDeltaFt * (Constants.DECIMAL_BASE + uint(feeConfig.borrowMakerFeeRatio))) / nif - negDeltaFt;
        tokenOut = ft;
    }

    function _buyExactXtStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint xtAmtOut,
        OrderConfig memory config
    ) internal view returns (uint debtTokenAmtIn, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint nif = Constants.DECIMAL_BASE + uint(feeConfig.borrowTakerFeeRatio);
        (, uint deltaFt) = TermMaxCurve.buyExactXt(nif, daysToMaturity, cuts, oriXtReserve, xtAmtOut);
        debtTokenAmtIn = deltaFt;
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint(feeConfig.lendMakerFeeRatio))) / nif;
        tokenOut = xt;
    }

    function _sellFtForExactToken(
        uint debtTokenAmtOut,
        uint maxFtIn,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isBorrowingAllowed(config) returns (uint256 netIn, uint256 feeAmt) {
        (netIn, feeAmt) = _sellTokenForExactToken(
            caller,
            recipient,
            debtTokenAmtOut,
            maxFtIn,
            config,
            _sellFtForExactTokenStep
        );
    }

    function _sellXtForExactToken(
        uint debtTokenAmtOut,
        uint maxXtIn,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isLendingAllowed(config) returns (uint256 netIn, uint256 feeAmt) {
        (netIn, feeAmt) = _sellTokenForExactToken(
            caller,
            recipient,
            debtTokenAmtOut,
            maxXtIn,
            config,
            _sellXtForExactTokenStep
        );
        if (xt.balanceOf(address(this)) > config.maxXtReserve) {
            revert XtReserveTooHigh();
        }
    }

    function _sellTokenForExactToken(
        address caller,
        address recipient,
        uint debtTokenAmtOut,
        uint maxTokenIn,
        OrderConfig memory config,
        function(uint, uint, uint, OrderConfig memory) internal view returns (uint, uint, IERC20) func
    ) internal returns (uint256, uint256) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = getTransientXtReserve();

        (uint netTokenIn, uint feeAmt, IERC20 tokenIn) = func(daysToMaturity, oriXtReserve, debtTokenAmtOut, config);

        if (netTokenIn > maxTokenIn) revert UnexpectedAmount(maxTokenIn, netTokenIn);

        tokenIn.safeTransferFrom(caller, address(this), netTokenIn);
        if (tokenIn == xt) {
            uint ftReserve = getTransientFtReserve();
            if (ftReserve < debtTokenAmtOut) _issueFt(recipient, ftReserve, debtTokenAmtOut + feeAmt, config);
        }
        ft.approve(address(market), debtTokenAmtOut);
        xt.approve(address(market), debtTokenAmtOut);
        market.burn(recipient, debtTokenAmtOut);
        return (netTokenIn, feeAmt);
    }

    function _sellFtForExactTokenStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenOut,
        OrderConfig memory config
    ) internal view returns (uint ftAmtIn, uint feeAmt, IERC20 tokenIn) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint nif = Constants.DECIMAL_BASE + uint(feeConfig.borrowTakerFeeRatio);

        (, uint deltaFt) = TermMaxCurve.sellFtForExactDebtToken(nif, daysToMaturity, cuts, oriXtReserve, debtTokenOut);
        ftAmtIn = deltaFt + debtTokenOut;

        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint(feeConfig.lendMakerFeeRatio))) / nif;
        tokenIn = ft;
    }

    function _sellXtForExactTokenStep(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenOut,
        OrderConfig memory config
    ) internal view returns (uint xtAmtIn, uint feeAmt, IERC20 tokenIn) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint nif = Constants.DECIMAL_BASE - uint(feeConfig.lendTakerFeeRatio);
        (uint deltaXt, uint negDeltaFt) = TermMaxCurve.sellXtForExactDebtToken(
            nif,
            daysToMaturity,
            cuts,
            oriXtReserve,
            debtTokenOut
        );
        xtAmtIn = deltaXt + debtTokenOut;

        feeAmt = (negDeltaFt * (Constants.DECIMAL_BASE + uint(feeConfig.borrowMakerFeeRatio))) / nif - negDeltaFt;
        tokenIn = xt;
    }

    function _issueFt(address recipient, uint ftReserve, uint targetFtReserve, OrderConfig memory config) internal {
        if (config.gtId == 0) revert CantNotIssueFtWithoutGt();
        uint ftAmtToIssue = ((targetFtReserve - ftReserve) * Constants.DECIMAL_BASE) /
            (Constants.DECIMAL_BASE - market.issueFtFeeRatio());
        market.issueFtByExistedGt(recipient, (ftAmtToIssue).toUint128(), config.gtId);
    }

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        token.safeTransfer(recipient, amount);
        emit WithdrawAssets(token, _msgSender(), recipient, amount);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function unpause() external override onlyOwner {
        _unpause();
    }
}
