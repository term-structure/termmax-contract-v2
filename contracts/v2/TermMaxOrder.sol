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
import {MarketConfig, CurveCuts, FeeConfig} from "./storage/TermMaxStorage.sol";
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

    bytes32 private curveCutsHash;

    CurveCuts private _curveCuts;

    FeeConfig private _feeConfig;

    address public maker;

    uint private gtId;

    uint64 private maturity;

    /// @notice Check if the market is borrowing allowed
    modifier isBorrowingAllowed() {
        if (_curveCuts.borrowCurveCuts.length == 0) {
            revert BorrowIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier isLendingAllowed() {
        if (_curveCuts.lendCurveCuts.length == 0) {
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
        CurveCuts memory curveCuts_,
        MarketConfig memory marketConfig
    ) external override {
        __Ownable_init(admin);
        __ReentrancyGuard_init();
        __Pausable_init();
        market = ITermMaxMarket(_msgSender());
        maker = maker_;
        _curveCuts = curveCuts_;
        maturity = marketConfig.maturity;
        _feeConfig = marketConfig.feeConfig;
        ft = tokens[0];
        xt = tokens[1];
        debtToken = tokens[2];
        gt = gt_;
        curveCutsHash = keccak256(abi.encode(curveCuts_));
        emit OrderInitialized(market, maker_, curveCuts_);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function curveCuts() external view returns (CurveCuts memory) {
        return _curveCuts;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function tokenReserves() public view override returns (uint256, uint256, uint256) {
        return (ft.balanceOf(address(this)), xt.balanceOf(address(this)), gtId);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function apr() external view override returns (uint256 lendApr_, uint256 borrowApr_) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = xt.balanceOf(address(this));

        CurveCuts memory __curveCuts = _curveCuts;

        uint lendCutId = TermMaxCurve.calcCutId(__curveCuts.lendCurveCuts, oriXtReserve);
        (, uint lendVXtReserve, uint lendVFtReserve) = TermMaxCurve.calcIntervalProps(
            daysToMaturity,
            __curveCuts.lendCurveCuts[lendCutId],
            oriXtReserve
        );
        lendApr_ =
            ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / lendVXtReserve) *
            daysToMaturity;

        uint borrowCutId = TermMaxCurve.calcCutId(__curveCuts.borrowCurveCuts, oriXtReserve);
        (, uint borrowVXtReserve, uint borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
            daysToMaturity,
            __curveCuts.borrowCurveCuts[borrowCutId],
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
        CurveCuts memory newCurveCuts,
        uint newFtReserve,
        uint newXtReserve,
        uint gtId_
    ) external override onlyMaker {
        _updateCurve(newCurveCuts);
        (uint xtReserve, uint ftReserve, uint _gtId) = tokenReserves();
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
        if (_gtId != gtId_) {
            gt.safeTransferFrom(maker, address(this), gtId_);
            gtId = gtId_;
        }

        emit UpdateOrder(newCurveCuts, ftReserve, xtReserve, gtId);
    }

    function _updateCurve(CurveCuts memory newCurveCuts) internal {
        bytes32 newCurveCutsHash = keccak256(abi.encode(newCurveCuts));
        if (curveCutsHash != newCurveCutsHash) {
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
            _curveCuts = newCurveCuts;
            curveCutsHash = newCurveCutsHash;
        }
    }

    function updateFeeConfig(FeeConfig memory newFeeConfig) external override onlyOwner {
        _feeConfig = newFeeConfig;
        _checkFee(newFeeConfig.borrowFeeRatio);
        _checkFee(newFeeConfig.lendFeeRatio);
        _checkFee(newFeeConfig.redeemFeeRatio);
        _checkFee(newFeeConfig.issueFtFeeRatio);
        _checkFee(newFeeConfig.minNBorrowFeeR);
        _checkFee(newFeeConfig.minNLendFeeR);
        emit UpdateFeeConfig(newFeeConfig);
    }

    function _checkFee(uint32 feeRatio) internal pure {
        if (feeRatio >= Constants.MAX_FEE_RATIO) revert FeeTooHigh();
    }

    function feeConfig() external view returns (FeeConfig memory) {
        return _feeConfig;
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
        uint feeAmt;
        if (tokenIn == ft && tokenOut == debtToken) {
            (netTokenOut, feeAmt) = sellFt(tokenAmtIn, minTokenOut, recipient);
        } else if (tokenIn == xt && tokenOut == debtToken) {
            (netTokenOut, feeAmt) = sellXt(tokenAmtIn, minTokenOut, recipient);
        } else if (tokenIn == debtToken && tokenOut == ft) {
            (netTokenOut, feeAmt) = buyFt(tokenAmtIn, minTokenOut, recipient);
        } else if (tokenIn == debtToken && tokenOut == xt) {
            (netTokenOut, feeAmt) = buyXt(tokenAmtIn, minTokenOut, recipient);
        } else if (tokenIn == ft && tokenOut == xt) {
            (uint debtTokenAmtOut, uint feeOneSide) = sellFt(tokenAmtIn, 0, address(this));
            (netTokenOut, feeAmt) = _buyToken(address(this), recipient, debtTokenAmtOut, minTokenOut, _buyXt);
            feeAmt += feeOneSide;
        } else if (tokenIn == xt && tokenOut == ft) {
            (uint debtTokenAmtOut, uint feeOneSide) = sellXt(tokenAmtIn, 0, address(this));
            (netTokenOut, feeAmt) = _buyToken(address(this), recipient, debtTokenAmtOut, minTokenOut, _buyFt);
            feeAmt += feeOneSide;
        } else {
            revert CantNotSwapToken(tokenIn, tokenOut);
        }
        debtToken.safeTransfer(market.config().treasurer, feeAmt);
        emit SwapExactTokenToToken(
            msg.sender,
            recipient,
            tokenIn,
            tokenOut,
            tokenAmtIn,
            netTokenOut.toUint128(),
            feeAmt.toUint128()
        );
    }

    function buyFt(
        uint debtTokenAmtIn,
        uint minTokenOut,
        address caller,
        address recipient
    ) internal isLendingAllowed returns (uint256 netOut, uint256 feeAmt) {
        return _buyToken(caller, recipient, debtTokenAmtIn, minTokenOut, _buyFt);
    }

    function buyXt(
        uint debtTokenAmtIn,
        uint minTokenOut,
        address caller,
        address recipient
    ) internal isBorrowingAllowed returns (uint256 netOut, uint256 feeAmt) {
        return _buyToken(caller, recipient, debtTokenAmtIn, minTokenOut, _buyXt);
    }

    function sellFt(
        uint ftAmtIn,
        uint minDebtTokenOut,
        address caller,
        address recipient
    ) internal isBorrowingAllowed returns (uint256 netOut, uint256 feeAmt) {
        return _sellToken(caller, recipient, ftAmtIn, minDebtTokenOut, _sellFt);
    }

    function sellXt(
        uint xtAmtIn,
        uint minDebtTokenOut,
        address caller,
        address recipient
    ) internal isLendingAllowed returns (uint256 netOut, uint256 feeAmt) {
        return _sellToken(caller, recipient, xtAmtIn, minDebtTokenOut, _sellXt);
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
        function(uint, uint, uint) internal view returns (uint, uint, IERC20) func
    ) internal returns (uint256, uint256) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) = func(daysToMaturity, oriXtReserve, debtTokenAmtIn);

        uint256 netOut = tokenAmtOut + debtTokenAmtIn - feeAmt;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        debtToken.safeTransferFrom(caller, address(this), debtTokenAmtIn);

        debtToken.approve(address(market), debtTokenAmtIn);
        market.mint(address(this), debtTokenAmtIn - feeAmt);
        uint ftReserve = ft.balanceOf(address(this));
        if (tokenOut == ft && ftReserve < netOut) {
            _issueFt(recipient, ftReserve, netOut);
        } else {
            tokenOut.safeTransfer(recipient, netOut);
        }
        return (netOut, feeAmt);
    }

    function _buyFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) {
        (, uint negDeltaFt) = TermMaxCurve.buyFt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            debtTokenAmtIn
        );
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (negDeltaFt * __feeConfig.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (debtTokenAmtIn * __feeConfig.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (, tokenAmtOut) = TermMaxCurve.buyFt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            debtTokenAmtIn - feeAmt
        );
        tokenOut = ft;
    }

    function _buyXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint debtTokenAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IERC20 tokenOut) {
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (debtTokenAmtIn * __feeConfig.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (debtTokenAmtIn * __feeConfig.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (tokenAmtOut, ) = TermMaxCurve.buyXt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            debtTokenAmtIn - feeAmt
        );
        tokenOut = xt;
    }

    function _sellToken(
        address caller,
        address recipient,
        uint tokenAmtIn,
        uint minDebtTokenOut,
        function(uint, uint, uint) internal view returns (uint, uint, IERC20) func
    ) internal returns (uint256, uint256) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn);

        uint netOut = debtTokenAmtOut - feeAmt;
        if (netOut < minDebtTokenOut) revert UnexpectedAmount(minDebtTokenOut, netOut);

        tokenIn.safeTransferFrom(caller, address(this), tokenAmtIn);

        if (tokenIn == xt) {
            uint ftReserve = ft.balanceOf(address(this));
            if (ftReserve < debtTokenAmtOut) _issueFt(recipient, ftReserve, debtTokenAmtOut);
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
        uint tokenAmtIn
    ) internal view returns (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) {
        uint deltaFt;
        (debtTokenAmtOut, deltaFt) = TermMaxCurve.sellFt(
            daysToMaturity,
            _curveCuts.lendCurveCuts,
            oriXtReserve,
            tokenAmtIn
        );
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (deltaFt * __feeConfig.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (debtTokenAmtOut * __feeConfig.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        tokenIn = ft;
    }

    function _sellXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint debtTokenAmtOut, uint feeAmt, IERC20 tokenIn) {
        (, debtTokenAmtOut) = TermMaxCurve.sellXt(daysToMaturity, _curveCuts.borrowCurveCuts, oriXtReserve, tokenAmtIn);
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (debtTokenAmtOut * __feeConfig.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (debtTokenAmtOut * __feeConfig.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        tokenIn = xt;
    }

    function _issueFt(address recipient, uint ftReserve, uint targetFtReserve) internal {
        if (gtId == 0) revert CantNotIssueFtWithoutGt();
        uint ftAmtToIssue = ((targetFtReserve - ftReserve) * Constants.DECIMAL_BASE) / _feeConfig.issueFtFeeRatio;
        market.issueFtByExistedGt(recipient, (ftAmtToIssue).toUint128(), gtId);
    }
}
