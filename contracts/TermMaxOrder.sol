// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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
import {ITradeCallback} from "./ITradeCallback.sol";
import {TransferUtils} from "./lib/TransferUtils.sol";

/**
 * @title TermMax Order
 * @author Term Structure Labs
 */
contract TermMaxOrder is
    ITermMaxOrder,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
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

    address public maker;

    uint64 private maturity;

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

    modifier onlyMaker() {
        if (msg.sender != maker) revert OnlyMaker();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function initialize(
        address admin,
        address maker_,
        IERC20[3] memory tokens,
        IGearingToken gt_,
        uint256 maxXtReserve_,
        CurveCuts memory curveCuts_,
        MarketConfig memory marketConfig
    ) external override initializer {
        __Ownable_init(admin);
        __ReentrancyGuard_init();
        __Pausable_init();
        market = ITermMaxMarket(_msgSender());
        maker = maker_;
        _orderConfig.curveCuts = curveCuts_;
        _orderConfig.feeConfig = marketConfig.feeConfig;
        _orderConfig.maxXtReserve = maxXtReserve_;
        maturity = marketConfig.maturity;

        ft = tokens[0];
        xt = tokens[1];
        debtToken = tokens[2];
        gt = gt_;
        emit OrderInitialized(market, maker_, maxXtReserve_, curveCuts_);
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
        lendApr_ =
            ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / lendVXtReserve) *
            daysToMaturity;

        uint borrowCutId = TermMaxCurve.calcCutId(curveCuts.borrowCurveCuts, oriXtReserve);
        (, uint borrowVXtReserve, uint borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
            Constants.DECIMAL_BASE,
            daysToMaturity,
            curveCuts.borrowCurveCuts[borrowCutId],
            oriXtReserve
        );
        borrowApr_ =
            ((borrowVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / borrowVXtReserve) *
            daysToMaturity;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function updateOrder(
        OrderConfig memory newOrderConfig,
        uint newFtReserve,
        uint newXtReserve
    ) external override onlyMaker {
        _updateCurve(newOrderConfig.curveCuts);
        (uint xtReserve, uint ftReserve) = tokenReserves();
        if (newFtReserve > ftReserve) {
            ft.safeTransferFrom(maker, address(this), newFtReserve - ftReserve);
        } else if (newFtReserve < ftReserve) {
            ft.safeTransfer(maker, ftReserve - newFtReserve);
        }
        if (newXtReserve > xtReserve) {
            xt.safeTransferFrom(maker, address(this), newXtReserve - xtReserve);
        } else if (newXtReserve < xtReserve) {
            xt.safeTransfer(maker, xtReserve - newXtReserve);
        }
        _orderConfig.maxXtReserve = newOrderConfig.maxXtReserve;
        // check gtId
        if (newOrderConfig.gtId != 0 && address(this) != gt.getApproved(newOrderConfig.gtId)) {
            revert GtNotApproved(newOrderConfig.gtId);
        }
        _orderConfig.gtId = newOrderConfig.gtId;
        emit UpdateOrder(
            newOrderConfig.curveCuts,
            ftReserve,
            xtReserve,
            newOrderConfig.gtId,
            newOrderConfig.maxXtReserve
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
            }
            if (newCurveCuts.borrowCurveCuts.length > 0) {
                if (newCurveCuts.borrowCurveCuts[0].xtReserve != 0) revert InvalidCurveCuts();
            }
            for (uint i = 1; i < newCurveCuts.borrowCurveCuts.length; i++) {
                if (newCurveCuts.borrowCurveCuts[i].xtReserve <= newCurveCuts.borrowCurveCuts[i - 1].xtReserve)
                    revert InvalidCurveCuts();
            }
            _orderConfig.curveCuts = newCurveCuts;
        }
    }

    function updateFeeConfig(FeeConfig memory newFeeConfig) external override onlyOwner {
        _checkFee(newFeeConfig.borrowTakerFeeRatio);
        _checkFee(newFeeConfig.borrowMakerFeeRatio);
        _checkFee(newFeeConfig.lendTakerFeeRatio);
        _checkFee(newFeeConfig.lendMakerFeeRatio);
        _checkFee(newFeeConfig.redeemFeeRatio);
        _checkFee(newFeeConfig.issueFtFeeRatio);
        _checkFee(newFeeConfig.issueFtFeeRef);
        _orderConfig.feeConfig = newFeeConfig;
        emit UpdateFeeConfig(newFeeConfig);
    }

    function _checkFee(uint32 feeRatio) internal pure {
        if (feeRatio >= Constants.MAX_FEE_RATIO) revert FeeTooHigh();
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
    ) external override nonReentrant whenNotPaused returns (uint256 netTokenOut) {
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        OrderConfig memory config = _orderConfig;
        uint feeAmt;
        if (tokenIn == ft && tokenOut == debtToken) {
            (netTokenOut, feeAmt) = sellFt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == xt && tokenOut == debtToken) {
            (netTokenOut, feeAmt) = sellXt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == debtToken && tokenOut == ft) {
            (netTokenOut, feeAmt) = buyFt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == debtToken && tokenOut == xt) {
            (netTokenOut, feeAmt) = buyXt(tokenAmtIn, minTokenOut, msg.sender, recipient, config);
        } else if (tokenIn == ft && tokenOut == xt) {
            (uint debtTokenAmtOut, uint feeOneSide) = sellFt(tokenAmtIn, 0, msg.sender, address(this), config);
            (netTokenOut, feeAmt) = buyXt(debtTokenAmtOut, minTokenOut, address(this), recipient, config);
            feeAmt += feeOneSide;
        } else if (tokenIn == xt && tokenOut == ft) {
            (uint debtTokenAmtOut, uint feeOneSide) = sellXt(tokenAmtIn, 0, msg.sender, address(this), config);
            (netTokenOut, feeAmt) = buyFt(debtTokenAmtOut, minTokenOut, address(this), recipient, config);
            feeAmt += feeOneSide;
        } else {
            revert CantNotSwapToken(tokenIn, tokenOut);
        }
        ft.safeTransfer(market.config().treasurer, feeAmt);

        if (maker.code.length > 0) {
            ITradeCallback(maker).tradeCallback(ft.balanceOf(address(this)));
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

    function buyFt(
        uint debtTokenAmtIn,
        uint minTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isLendingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        (netOut, feeAmt) = _buyToken(caller, recipient, debtTokenAmtIn, minTokenOut, config, _buyFt);
        if (xt.balanceOf(address(this)) > config.maxXtReserve) {
            revert XtReserveTooHigh();
        }
    }

    function buyXt(
        uint debtTokenAmtIn,
        uint minTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isBorrowingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        return _buyToken(caller, recipient, debtTokenAmtIn, minTokenOut, config, _buyXt);
    }

    function sellFt(
        uint ftAmtIn,
        uint minDebtTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isBorrowingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        return _sellToken(caller, recipient, ftAmtIn, minDebtTokenOut, config, _sellFt);
    }

    function sellXt(
        uint xtAmtIn,
        uint minDebtTokenOut,
        address caller,
        address recipient,
        OrderConfig memory config
    ) internal isLendingAllowed(config) returns (uint256 netOut, uint256 feeAmt) {
        (netOut, feeAmt) = _sellToken(caller, recipient, xtAmtIn, minDebtTokenOut, config, _sellXt);
        if (xt.balanceOf(address(this)) > config.maxXtReserve) {
            revert XtReserveTooHigh();
        }
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function pause() external override onlyMaker {
        _pause();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function unpause() external override onlyMaker {
        _unpause();
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
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) = func(daysToMaturity, oriXtReserve, debtTokenAmtIn, config);

        uint256 netOut = tokenAmtOut + debtTokenAmtIn;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        debtToken.safeTransferFrom(caller, address(this), debtTokenAmtIn);

        debtToken.approve(address(market), debtTokenAmtIn);
        market.mint(address(this), debtTokenAmtIn);
        uint ftReserve = ft.balanceOf(address(this));
        if (tokenOut == ft && ftReserve < netOut + feeAmt) _issueFt(address(this), ftReserve, netOut + feeAmt, config);
        tokenOut.safeTransfer(recipient, netOut);

        return (netOut, feeAmt);
    }

    function _buyFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint nif = Constants.DECIMAL_BASE - feeConfig.lendTakerFeeRatio;
        (, tokenAmtOut) = TermMaxCurve.buyFt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = (tokenAmtOut * (Constants.DECIMAL_BASE + feeConfig.borrowMakerFeeRatio)) / nif - tokenAmtOut;
        tokenOut = ft;
    }

    function _buyXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint nif = Constants.DECIMAL_BASE + feeConfig.borrowTakerFeeRatio;
        uint deltaFt;
        (tokenAmtOut, deltaFt) = TermMaxCurve.buyXt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - feeConfig.lendMakerFeeRatio)) / nif;
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
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn, config);

        uint netOut = debtTokenAmtOut;
        if (netOut < minDebtTokenOut) revert UnexpectedAmount(minDebtTokenOut, netOut);

        tokenIn.safeTransferFrom(caller, address(this), tokenAmtIn);

        if (tokenIn == xt) {
            uint ftReserve = ft.balanceOf(address(this));
            if (ftReserve < debtTokenAmtOut) _issueFt(recipient, ftReserve, debtTokenAmtOut + feeAmt, config);
        }
        ft.approve(address(market), debtTokenAmtOut);
        xt.approve(address(market), debtTokenAmtOut);
        market.burn(address(this), debtTokenAmtOut);
        debtToken.safeTransfer(recipient, netOut);
        return (netOut, feeAmt);
    }

    function _sellFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint nif = Constants.DECIMAL_BASE + feeConfig.borrowTakerFeeRatio;
        uint deltaFt;
        (debtTokenAmtOut, deltaFt) = TermMaxCurve.sellFt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - feeConfig.lendMakerFeeRatio)) / nif;
        tokenIn = ft;
    }

    function _sellXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn,
        OrderConfig memory config
    ) internal view returns (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint nif = Constants.DECIMAL_BASE - feeConfig.lendTakerFeeRatio;
        (, debtTokenAmtOut) = TermMaxCurve.sellXt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = (debtTokenAmtOut * (Constants.DECIMAL_BASE + feeConfig.borrowMakerFeeRatio)) / nif - debtTokenAmtOut;
        tokenIn = ft;
    }

    function _issueFt(address recipient, uint ftReserve, uint targetFtReserve, OrderConfig memory config) internal {
        if (config.gtId == 0) revert CantNotIssueFtWithoutGt();
        uint ftAmtToIssue = ((targetFtReserve - ftReserve) * Constants.DECIMAL_BASE) / market.issueFtFeeRatio();
        market.issueFtByExistedGt(recipient, (ftAmtToIssue).toUint128(), config.gtId);
    }

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external onlyMaker {
        token.safeTransfer(recipient, amount);
        emit WithdrawAssets(token, _msgSender(), recipient, amount);
    }
}
