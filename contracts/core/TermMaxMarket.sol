// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITermMaxMarket, MarketConfig, IMintableERC20, IERC20} from "./ITermMaxMarket.sol";
import {TokenPairConfig} from "./storage/TermMaxStorage.sol";
import {ITermMaxTokenPair} from "./ITermMaxTokenPair.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {Constants} from "./lib/Constants.sol";
import {Ownable} from "./access/Ownable.sol";
import {TermMaxCurve, MathLib} from "./lib/TermMaxCurve.sol";

/**
 * @title TermMax Market
 * @author Term Structure Labs
 */
contract TermMaxMarket is ITermMaxMarket, ReentrancyGuard, Ownable, Pausable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;

    MarketConfig private _config;
    ITermMaxTokenPair private _tokenPair;
    uint gtId = type(uint256).max;
    address provider;

    /// @notice Check if the market is tradable
    modifier isOpen() {
        _requireNotPaused();
        TokenPairConfig memory config_ = _tokenPair.config();
        if (block.timestamp < config_.openTime || block.timestamp >= config_.maturity) {
            revert MarketIsNotOpen();
        }
        _;
    }

    /// @notice Check if the market is borrowing allowed
    modifier isBorrowingAllowed() {
        if (_config.borrowCurveCuts.length == 0) {
            revert TOBEDEFINED();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier isLendingAllowed() {
        if (_config.lendCurveCuts.length == 0) {
            revert TOBEDEFINED();
        }
        _;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function initialize(address admin, ITermMaxTokenPair tokenPair_, MarketConfig memory config_) external override {
        __initializeOwner(admin);
        _tokenPair = tokenPair_;
        _config = config_;
        emit MarketInitialized(tokenPair_);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function config() public view override returns (MarketConfig memory) {
        return _config;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function ftXtReserves() public view override returns (uint256, uint256) {
        (IMintableERC20 ft, IMintableERC20 xt, , , ) = _tokenPair.tokens();
        uint256 ftReserve = ft.balanceOf(address(this));
        uint256 xtReserve = xt.balanceOf(address(this));
        return (ftReserve, xtReserve);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function tokenPair() external view override returns (ITermMaxTokenPair) {
        return _tokenPair;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function tokens() external view override returns (IMintableERC20, IMintableERC20, IGearingToken, address, IERC20) {
        return _tokenPair.tokens();
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function apr() external view override returns (uint lendApr_, uint borrowApr_) {
        (, IMintableERC20 xt, , , ) = _tokenPair.tokens();
        uint daysToMaturity = _daysToMaturity(_tokenPair.config().maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        uint lendCutId = TermMaxCurve.calcCutId(_config.lendCurveCuts, oriXtReserve);
        (, uint lendVXtReserve, uint lendVFtReserve) = TermMaxCurve.calcIntervalProps(
            daysToMaturity,
            _config.lendCurveCuts[lendCutId],
            oriXtReserve
        );
        lendApr_ = ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / lendVXtReserve) * daysToMaturity;

        uint borrowCutId = TermMaxCurve.calcCutId(_config.borrowCurveCuts, oriXtReserve);
        (, uint borrowVXtReserve, uint borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
            daysToMaturity,
            _config.borrowCurveCuts[borrowCutId],
            oriXtReserve
        );
        borrowApr_ = ((borrowVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / borrowVXtReserve) * daysToMaturity;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateMarketConfig(
        MarketConfig calldata newConfig,
        uint newFtReserve,
        uint newXtReserve,
        uint gtId_
    ) external override onlyOwner {
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, , ) = _tokenPair.tokens();
        if (newConfig.maker != _config.maker) revert TOBEDEFINED();
        if (newConfig.treasurer != _config.treasurer) revert TOBEDEFINED();
        if (newConfig.lendCurveCuts.length > 0) {
            if (newConfig.lendCurveCuts[0].xtReserve != 0) revert TOBEDEFINED();
        }
        for (uint i = 1; i < newConfig.lendCurveCuts.length; i++) {
            if (newConfig.lendCurveCuts[i].xtReserve <= newConfig.lendCurveCuts[i - 1].xtReserve) revert TOBEDEFINED();
        }
        if (newConfig.borrowCurveCuts.length > 0) {
            if (newConfig.borrowCurveCuts[0].xtReserve != 0) revert TOBEDEFINED();
        }
        for (uint i = 1; i < newConfig.borrowCurveCuts.length; i++) {
            if (newConfig.borrowCurveCuts[i].xtReserve <= newConfig.borrowCurveCuts[i - 1].xtReserve)
                revert TOBEDEFINED();
        }
        _config = newConfig;

        (uint xtReserve, uint ftReserve) = ftXtReserves();
        if (newFtReserve > ftReserve) {
            ft.safeTransferFrom(_config.maker, address(this), newFtReserve - ftReserve);
        } else if (newFtReserve < ftReserve) {
            ft.safeTransfer(_config.maker, ftReserve - newFtReserve);
        }
        if (newXtReserve > xtReserve) {
            xt.safeTransferFrom(_config.maker, address(this), newXtReserve - xtReserve);
        } else if (newXtReserve < xtReserve) {
            xt.safeTransfer(_config.maker, xtReserve - newXtReserve);
        }
        if (gtId != gtId_) {
            if (gtId != type(uint256).max) gt.safeTransferFrom(address(this), _config.maker, gtId);
            gt.safeTransferFrom(_config.maker, address(this), gtId_);
            gtId = gtId_;
        }

        emit UpdateMarketConfig(_config);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function setProvider(address provider_) external override onlyOwner {
        provider = provider_;
        emit UpdateProvider(provider);
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity(uint maturity) internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyFt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isOpen isLendingAllowed returns (uint256 netOut) {
        return _buyToken(underlyingAmtIn, minTokenOut, _buyFt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isOpen isBorrowingAllowed returns (uint256 netOut) {
        return _buyToken(underlyingAmtIn, minTokenOut, _buyXt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen isBorrowingAllowed returns (uint256 netOut) {
        return _sellToken(ftAmtIn, minUnderlyingOut, _sellFt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen isLendingAllowed returns (uint256 netOut) {
        return _sellToken(xtAmtIn, minUnderlyingOut, _sellXt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    function _buyToken(
        uint128 underlyingAmtIn,
        uint128 minTokenOut,
        function(uint, uint, uint) internal view returns (uint, uint, bool) func
    ) internal returns (uint256 netOut) {
        (IMintableERC20 ft, IMintableERC20 xt, , , IERC20 underlying) = _tokenPair.tokens();
        uint daysToMaturity = _daysToMaturity(_tokenPair.config().maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint tokenAmtOut, uint feeAmt, bool isXtOut) = func(daysToMaturity, oriXtReserve, underlyingAmtIn);
        IMintableERC20 tokenOut = isXtOut ? xt : ft;

        netOut = tokenAmtOut + underlyingAmtIn - feeAmt;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmtIn);
        underlying.safeTransfer(_config.treasurer, feeAmt);
        underlying.approve(address(_tokenPair), underlyingAmtIn);
        _tokenPair.mintFtAndXt(address(this), address(this), underlyingAmtIn - feeAmt);

        uint ftReserve = ft.balanceOf(address(this));
        if (tokenOut == ft && ftReserve < netOut) {
            _issueFt(msg.sender, ftReserve, netOut);
            tokenOut.safeTransfer(msg.sender, ftReserve);
        } else {
            tokenOut.safeTransfer(msg.sender, netOut);
        }
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
    ) internal view returns (uint tokenAmtOut, uint feeAmt, bool isXtOut) {
        (, uint negDeltaFt) = TermMaxCurve.buyFt(daysToMaturity, _config.borrowCurveCuts, oriXtReserve, underlyingAmtIn);
        feeAmt = (negDeltaFt * _config.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtIn * _config.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (, tokenAmtOut) = TermMaxCurve.buyFt(daysToMaturity, _config.borrowCurveCuts, oriXtReserve, underlyingAmtIn - feeAmt);
        isXtOut = false;
    }

    function _buyXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint underlyingAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, bool isXtOut) {
        feeAmt = (underlyingAmtIn * _config.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtIn * _config.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (tokenAmtOut, ) = TermMaxCurve.buyXt(daysToMaturity, _config.lendCurveCuts, oriXtReserve, underlyingAmtIn - feeAmt);
        isXtOut = true;
    }

    function _sellToken(
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut,
        function(uint, uint, uint) internal view returns (uint, uint, bool) func
    ) internal returns (uint256 netOut) {
        (IMintableERC20 ft, IMintableERC20 xt, , , IERC20 underlying) = _tokenPair.tokens();
        uint daysToMaturity = _daysToMaturity(_tokenPair.config().maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint underlyingAmtOut, uint feeAmt, bool isXtIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn);
        IMintableERC20 tokenIn = isXtIn ? xt : ft;

        netOut = underlyingAmtOut - feeAmt;
        if (netOut < minUnderlyingOut) revert UnexpectedAmount(minUnderlyingOut, netOut);

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);
        if (tokenIn == xt) {
            uint ftReserve = ft.balanceOf(address(this));
            if (ftReserve < underlyingAmtOut) _issueFt(address(this), ftReserve, underlyingAmtOut);
        }
        ft.approve(address(_tokenPair), underlyingAmtOut);
        xt.approve(address(_tokenPair), underlyingAmtOut);
        _tokenPair.redeemFtAndXtToUnderlying(address(this), address(this), underlyingAmtOut);
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
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, bool isXtIn) {
        uint deltaFt;
        (underlyingAmtOut, deltaFt) = TermMaxCurve.sellFt(daysToMaturity, _config.lendCurveCuts, oriXtReserve, tokenAmtIn);
        feeAmt = (deltaFt * _config.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtOut * _config.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        isXtIn = false;
    }

    function _sellXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, bool isXtIn) {
        (, underlyingAmtOut) = TermMaxCurve.sellXt(daysToMaturity, _config.borrowCurveCuts, oriXtReserve, tokenAmtIn);
        feeAmt = (underlyingAmtOut * _config.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtOut * _config.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        isXtIn = true;
    }

    function _issueFt(address receiver, uint ftReserve, uint targetFtReserve) internal {
        if (gtId == type(uint256).max) revert TOBEDEFINED();
        TokenPairConfig memory config_ = _tokenPair.config();
        uint ftAmtToIssue = ((targetFtReserve - ftReserve) * Constants.DECIMAL_BASE) / config_.issueFtFeeRatio;
        _tokenPair.issueFtByExistedGt(receiver, (ftAmtToIssue).toUint128(), gtId);
    }
}
