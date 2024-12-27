// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITermMaxOrder, IMintableERC20, IERC20} from "./ITermMaxOrder.sol";
import {TokenPairConfig} from "./storage/TermMaxStorage.sol";
import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {Constants} from "./lib/Constants.sol";
import {Ownable} from "./access/Ownable.sol";
import {TermMaxCurve, MathLib} from "./lib/TermMaxCurve.sol";
import {OrderErrors} from "./errors/OrderErrors.sol";
import {OrderEvents} from "./events/OrderEvents.sol";
import {CurveCuts, FeeConfig} from "./storage/TermMaxStorage.sol";

/**
 * @title TermMax Order
 * @author Term Structure Labs
 */
contract TermMaxOrder is ITermMaxOrder, ReentrancyGuard, Ownable, Pausable, OrderErrors, OrderEvents {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;

    ITermMaxMarket public market;

    IMintableERC20 private ft;
    IMintableERC20 private xt;
    IERC20 private underlying;
    IGearingToken private gt;

    bytes32 private curveCutsHash;

    CurveCuts private _curveCuts;

    FeeConfig private _feeConfig;

    address public maker;

    address private treasurer;

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

    /**
     * @inheritdoc ITermMaxOrder
     */
    function initialize(
        address admin,
        ITermMaxMarket market_,
        address maker_,
        CurveCuts memory curveCuts_
    ) external override {
        __initializeOwner(admin);
        market = market_;
        maker = maker_;
        _curveCuts = curveCuts_;
        (ft, xt, gt, , underlying) = market.tokens();
        curveCutsHash = keccak256(abi.encode(curveCuts_));
        emit OrderInitialized(market_);
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
        emit UpdateFeeConfig(newFeeConfig);
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
    function buyFt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isLendingAllowed whenNotPaused returns (uint256 netOut) {
        return _buyToken(underlyingAmtIn, minTokenOut, _buyFt);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isBorrowingAllowed whenNotPaused returns (uint256 netOut) {
        return _buyToken(underlyingAmtIn, minTokenOut, _buyXt);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isBorrowingAllowed whenNotPaused returns (uint256 netOut) {
        return _sellToken(ftAmtIn, minUnderlyingOut, _sellFt);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isLendingAllowed whenNotPaused returns (uint256 netOut) {
        return _sellToken(xtAmtIn, minUnderlyingOut, _sellXt);
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
        uint128 underlyingAmtIn,
        uint128 minTokenOut,
        function(uint, uint, uint) internal view returns (uint, uint, IMintableERC20) func
    ) internal returns (uint256 netOut) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint tokenAmtOut, uint feeAmt, IMintableERC20 tokenOut) = func(daysToMaturity, oriXtReserve, underlyingAmtIn);

        netOut = tokenAmtOut + underlyingAmtIn - feeAmt;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmtIn);
        underlying.safeTransfer(treasurer, feeAmt);
        underlying.approve(address(market), underlyingAmtIn);
        market.mintFtAndXt(address(this), underlyingAmtIn - feeAmt);
        uint ftReserve = ft.balanceOf(address(this));
        if (tokenOut == ft && ftReserve < netOut) {
            _issueFt(msg.sender, ftReserve, netOut);
        }
        tokenOut.safeTransfer(msg.sender, netOut);
        emit BuyToken(
            msg.sender,
            tokenOut,
            underlyingAmtIn,
            minTokenOut,
            netOut,
            feeAmt,
            ft.balanceOf(address(this)),
            xt.balanceOf(address(this))
        );
    }

    function _buyFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint underlyingAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IMintableERC20 tokenOut) {
        (, uint negDeltaFt) = TermMaxCurve.buyFt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            underlyingAmtIn
        );
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (negDeltaFt * __feeConfig.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtIn * __feeConfig.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (, tokenAmtOut) = TermMaxCurve.buyFt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            underlyingAmtIn - feeAmt
        );
        tokenOut = ft;
    }

    function _buyXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint underlyingAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IMintableERC20 tokenOut) {
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (underlyingAmtIn * __feeConfig.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtIn * __feeConfig.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (tokenAmtOut, ) = TermMaxCurve.buyXt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            underlyingAmtIn - feeAmt
        );
        tokenOut = xt;
    }

    function _sellToken(
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut,
        function(uint, uint, uint) internal view returns (uint, uint, IMintableERC20) func
    ) internal returns (uint256 netOut) {
        uint daysToMaturity = _daysToMaturity();
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint underlyingAmtOut, uint feeAmt, IMintableERC20 tokenIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn);

        netOut = underlyingAmtOut - feeAmt;
        if (netOut < minUnderlyingOut) revert UnexpectedAmount(minUnderlyingOut, netOut);

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);
        if (tokenIn == xt) {
            uint ftReserve = ft.balanceOf(address(this));
            if (ftReserve < underlyingAmtOut) _issueFt(address(this), ftReserve, underlyingAmtOut);
        }
        ft.approve(address(market), underlyingAmtOut);
        xt.approve(address(market), underlyingAmtOut);
        market.redeemFtAndXtToUnderlying(address(this), underlyingAmtOut);
        underlying.safeTransfer(msg.sender, netOut);
        emit SellToken(
            msg.sender,
            tokenIn,
            tokenAmtIn,
            minUnderlyingOut,
            netOut,
            feeAmt,
            ft.balanceOf(address(this)),
            xt.balanceOf(address(this))
        );
    }

    function _sellFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, IMintableERC20 tokenIn) {
        uint deltaFt;
        (underlyingAmtOut, deltaFt) = TermMaxCurve.sellFt(
            daysToMaturity,
            _curveCuts.lendCurveCuts,
            oriXtReserve,
            tokenAmtIn
        );
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (deltaFt * __feeConfig.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtOut * __feeConfig.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        tokenIn = ft;
    }

    function _sellXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, IMintableERC20 tokenIn) {
        (, underlyingAmtOut) = TermMaxCurve.sellXt(
            daysToMaturity,
            _curveCuts.borrowCurveCuts,
            oriXtReserve,
            tokenAmtIn
        );
        FeeConfig memory __feeConfig = _feeConfig;
        feeAmt = (underlyingAmtOut * __feeConfig.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtOut * __feeConfig.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        tokenIn = xt;
    }

    function _issueFt(address receiver, uint ftReserve, uint targetFtReserve) internal {
        if (gtId == 0) revert CantNotIssueFtWithoutGt();
        TokenPairConfig memory config_ = market.config();
        uint ftAmtToIssue = ((targetFtReserve - ftReserve) * Constants.DECIMAL_BASE) / config_.issueFtFeeRatio;
        market.issueFtByExistedGt(receiver, (ftAmtToIssue).toUint128(), gtId);
    }
}
