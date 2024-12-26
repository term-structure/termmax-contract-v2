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
    address provider;

    IMintableERC20 private ft;
    IMintableERC20 private xt;
    IERC20 private underlying;

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
        if (_config.isLendOnly) {
            revert TOBEDEFINED();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier isLendingAllowed() {
        if (_config.isBorrowOnly) {
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
        (IMintableERC20 ft_, IMintableERC20 xt_, , , IERC20 underlying_) = _tokenPair.tokens();

        ft = ft_;
        xt = xt_;
        underlying = underlying_;

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
    function apr() external view override returns (uint apr_) {
        uint daysToMaturity = _daysToMaturity(_tokenPair.config().maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        uint cutId = TermMaxCurve.calcCutId(_config.curveCuts, oriXtReserve);
        (, uint vXtReserve, uint vFtReserve) = TermMaxCurve.calcIntervalProps(
            daysToMaturity,
            _config.curveCuts[cutId],
            oriXtReserve
        );
        apr_ = ((vFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / vXtReserve) * daysToMaturity;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateMarketConfig(
        MarketConfig calldata newConfig,
        uint newFtReserve,
        uint newXtReserve
    ) external override onlyOwner {
        if (newConfig.maker != _config.maker) revert TOBEDEFINED();
        if (newConfig.treasurer != _config.treasurer) revert TOBEDEFINED();
        if (newConfig.curveCuts.length == 0) revert TOBEDEFINED();
        if (newConfig.curveCuts[0].xtReserve != 0) revert TOBEDEFINED();
        for (uint i = 1; i < newConfig.curveCuts.length; i++) {
            if (newConfig.curveCuts[i].xtReserve <= newConfig.curveCuts[i - 1].xtReserve) revert TOBEDEFINED();
        }
        if (newConfig.isBorrowOnly && newConfig.isLendOnly) revert TOBEDEFINED();
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
        function(uint, uint, uint) internal view returns (uint, uint, IMintableERC20) func
    ) internal returns (uint256 netOut) {
        uint daysToMaturity = _daysToMaturity(_tokenPair.config().maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint tokenAmtOut, uint feeAmt, IMintableERC20 tokenOut) = func(daysToMaturity, oriXtReserve, underlyingAmtIn);

        netOut = tokenAmtOut + underlyingAmtIn - feeAmt;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);

        underlying.safeTransferFrom(msg.sender, address(this), underlyingAmtIn);
        underlying.safeTransfer(_config.treasurer, feeAmt);
        underlying.approve(address(_tokenPair), underlyingAmtIn);
        _tokenPair.mintFtAndXt(address(this), underlyingAmtIn - feeAmt);
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
        (, uint negDeltaFt) = TermMaxCurve.buyFt(daysToMaturity, _config.curveCuts, oriXtReserve, underlyingAmtIn);
        feeAmt = (negDeltaFt * _config.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtIn * _config.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (, tokenAmtOut) = TermMaxCurve.buyFt(daysToMaturity, _config.curveCuts, oriXtReserve, underlyingAmtIn - feeAmt);
        tokenOut = ft;
    }

    function _buyXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint underlyingAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, IMintableERC20 tokenOut) {
        feeAmt = (underlyingAmtIn * _config.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtIn * _config.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        (tokenAmtOut, ) = TermMaxCurve.buyXt(daysToMaturity, _config.curveCuts, oriXtReserve, underlyingAmtIn - feeAmt);
        tokenOut = xt;
    }

    function _sellToken(
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut,
        function(uint, uint, uint) internal view returns (uint, uint, IMintableERC20) func
    ) internal returns (uint256 netOut) {
        uint daysToMaturity = _daysToMaturity(_tokenPair.config().maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint underlyingAmtOut, uint feeAmt, IMintableERC20 tokenIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn);

        netOut = underlyingAmtOut - feeAmt;
        if (netOut < minUnderlyingOut) revert UnexpectedAmount(minUnderlyingOut, netOut);

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);
        ft.approve(address(_tokenPair), underlyingAmtOut);
        xt.approve(address(_tokenPair), underlyingAmtOut);
        _tokenPair.redeemFtAndXtToUnderlying(address(this), underlyingAmtOut);
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
        (underlyingAmtOut, deltaFt) = TermMaxCurve.sellFt(daysToMaturity, _config.curveCuts, oriXtReserve, tokenAmtIn);
        feeAmt = (deltaFt * _config.borrowFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtOut * _config.minNBorrowFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        tokenIn = ft;
    }

    function _sellXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, IMintableERC20 tokenIn) {
        (, underlyingAmtOut) = TermMaxCurve.sellXt(daysToMaturity, _config.curveCuts, oriXtReserve, tokenAmtIn);
        feeAmt = (underlyingAmtOut * _config.lendFeeRatio) / Constants.DECIMAL_BASE;
        uint minFeeAmt = (underlyingAmtOut * _config.minNLendFeeR) / Constants.DECIMAL_BASE;
        feeAmt = feeAmt < minFeeAmt ? minFeeAmt : feeAmt;
        tokenIn = xt;
    }
}
