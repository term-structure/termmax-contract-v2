// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITermMaxMarket, MarketConfig, IMintableERC20, IERC20} from "./ITermMaxMarket.sol";
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

    /// @notice Check if the market is tradable
    modifier isOpen() {
        _requireNotPaused();
        if (block.timestamp < _config.openTime || block.timestamp >= _config.maturity) {
            revert MarketIsNotOpen();
        }
        _;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function initialize(address admin, ITermMaxTokenPair tokenPair_, MarketConfig memory config_) external override {
        __initializeOwner(admin);
        if (config_.openTime < block.timestamp || config_.maturity < config_.openTime)
            revert InvalidTime(config_.openTime, config_.maturity);

        _config = config_;

        emit MarketInitialized(tokenPair_, _config.openTime, _config.maturity);
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
    function updateMarketConfig(
        MarketConfig calldata newConfig,
        uint newFtReserve,
        uint newXtReserve
    ) external override onlyOwner {
        (IMintableERC20 ft, IMintableERC20 xt, , , ) = _tokenPair.tokens();
        if (newConfig.openTime != _config.openTime) revert TOBEDEFINED();
        if (newConfig.maturity != _config.maturity) revert TOBEDEFINED();
        if (newConfig.maker != _config.maker) revert TOBEDEFINED();
        if (newConfig.treasurer != _config.treasurer) revert TOBEDEFINED();
        if (newConfig.curveCuts.length == 0) revert TOBEDEFINED();
        if (newConfig.curveCuts[0].xtReserve != 0) revert TOBEDEFINED();
        for (uint i = 1; i < newConfig.curveCuts.length; i++) {
            if (newConfig.curveCuts[i].xtReserve <= newConfig.curveCuts[i - 1].xtReserve) revert TOBEDEFINED();
        }
        if (newConfig.isBorrowOnly && newConfig.isLendOly) revert TOBEDEFINED();
        _config = newConfig;

        (uint xtReserve, uint ftReserve) = ftXtReserves();
        if (newFtReserve > ftReserve) {
            ft.safeTransferFrom(msg.sender, address(this), newFtReserve - ftReserve);
        } else if (newFtReserve < ftReserve) {
            ft.safeTransfer(msg.sender, ftReserve - newFtReserve);
        }
        if (newXtReserve > xtReserve) {
            xt.safeTransferFrom(msg.sender, address(this), newXtReserve - xtReserve);
        } else if (newXtReserve < xtReserve) {
            xt.safeTransfer(msg.sender, xtReserve - newXtReserve);
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
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        return _buyToken(underlyingAmtIn, minTokenOut, _buyFt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        return _buyToken(underlyingAmtIn, minTokenOut, _buyXt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        return _sellToken(ftAmtIn, minUnderlyingOut, _sellFt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
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
        uint daysToMaturity = _daysToMaturity(_config.maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint tokenAmtOut, uint feeAmt, bool isXtOut) = func(daysToMaturity, oriXtReserve, underlyingAmtIn);
        IMintableERC20 tokenOut = isXtOut ? xt : ft;

        netOut = tokenAmtOut + underlyingAmtIn - feeAmt;
        if (netOut < minTokenOut) revert TOBEDEFINED();

        underlying.safeTransferFrom(msg.sender, _config.treasurer, feeAmt);
        _tokenPair.mintFtAndXt(msg.sender, address(this), underlyingAmtIn - feeAmt);
        tokenOut.safeTransfer(msg.sender, netOut);
    }

    function _buyFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint underlyingAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, bool isXtOut) {
        (, uint negDeltaFt) = TermMaxCurve.buyFt(daysToMaturity, _config.curveCuts, oriXtReserve, underlyingAmtIn);
        feeAmt = (negDeltaFt * _config.lendFeeRatio) / Constants.DECIMAL_BASE;
        (, tokenAmtOut) = TermMaxCurve.buyFt(daysToMaturity, _config.curveCuts, oriXtReserve, underlyingAmtIn - feeAmt);
        isXtOut = false;
    }

    function _buyXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint underlyingAmtIn
    ) internal view returns (uint tokenAmtOut, uint feeAmt, bool isXtOut) {
        feeAmt = (underlyingAmtIn * _config.borrowFeeRatio) / Constants.DECIMAL_BASE;
        (tokenAmtOut, ) = TermMaxCurve.buyXt(daysToMaturity, _config.curveCuts, oriXtReserve, underlyingAmtIn - feeAmt);
        isXtOut = true;
    }

    function _sellToken(
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut,
        function(uint, uint, uint) internal view returns (uint, uint, bool) func
    ) internal returns (uint256 netOut) {
        (IMintableERC20 ft, IMintableERC20 xt, , , IERC20 underlying) = _tokenPair.tokens();
        uint daysToMaturity = _daysToMaturity(_config.maturity);
        uint oriXtReserve = xt.balanceOf(address(this));

        (uint underlyingAmtOut, uint feeAmt, bool isXtIn) = func(daysToMaturity, oriXtReserve, tokenAmtIn);
        IMintableERC20 tokenIn = isXtIn ? xt : ft;

        netOut = underlyingAmtOut - feeAmt;
        if (netOut < minUnderlyingOut) revert TOBEDEFINED();

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);
        _tokenPair.redeemFtAndXtToUnderlying(address(this), address(this), underlyingAmtOut);
        underlying.safeTransfer(msg.sender, netOut);
    }

    function _sellFt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, bool isXtIn) {
        uint deltaFt;
        (underlyingAmtOut, deltaFt) = TermMaxCurve.sellFt(daysToMaturity, _config.curveCuts, oriXtReserve, tokenAmtIn);
        feeAmt = (deltaFt * _config.borrowFeeRatio) / Constants.DECIMAL_BASE;
        isXtIn = false;
    }

    function _sellXt(
        uint daysToMaturity,
        uint oriXtReserve,
        uint tokenAmtIn
    ) internal view returns (uint underlyingAmtOut, uint feeAmt, bool isXtIn) {
        (, underlyingAmtOut) = TermMaxCurve.sellXt(daysToMaturity, _config.curveCuts, oriXtReserve, tokenAmtIn);
        feeAmt = (underlyingAmtOut * _config.lendFeeRatio) / Constants.DECIMAL_BASE;
        isXtIn = true;
    }
}
