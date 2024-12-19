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
import {TermMaxCurve} from "./lib/TermMaxCurve.sol";

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
    function updateMarketConfig(MarketConfig calldata newConfig) external override onlyOwner {
        (, , IGearingToken gt, , ) = _tokenPair.tokens();
        if (newConfig.openTime != _config.openTime) revert TOBEDEFINED();
        if (newConfig.maturity != _config.maturity) revert TOBEDEFINED();
        if (newConfig.maker != _config.maker) revert TOBEDEFINED();
        if (newConfig.treasurer != _config.treasurer) {
            gt.setTreasurer(newConfig.treasurer);
        }
        _config = newConfig;
        emit UpdateMarketConfig(_config);
        //TODO: check xtReserve of cuts is increasing and start from zero
        //TODO: check apr of cuts is decreasing
        //TODO: adjust ft and xt reserves
        //TODO: only lend/ only borrow
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
        revert TODO();
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        revert TODO();
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        revert TODO();
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        revert TODO();
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
}
