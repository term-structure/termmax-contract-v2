// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITermMaxTokenPair, TokenPairConfig, IMintableERC20, IERC20} from "./ITermMaxTokenPair.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {Constants} from "./lib/Constants.sol";
import {Ownable} from "./access/Ownable.sol";

/**
 * @title TermMax Token Pair
 * @author Term Structure Labs
 */
contract TermMaxTokenPair is ITermMaxTokenPair, ReentrancyGuard, Ownable, Pausable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;

    TokenPairConfig private _config;
    address private collateral;
    IERC20 private underlying;
    IMintableERC20 private ft;
    IMintableERC20 private xt;
    IGearingToken private gt;

    /// @notice Check if the market is tradable
    modifier isOpen() {
        _requireNotPaused();
        if (block.timestamp < _config.openTime || block.timestamp >= _config.maturity) {
            revert TermIsNotOpen();
        }
        _;
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function initialize(
        address admin,
        address collateral_,
        IERC20 underlying_,
        IMintableERC20 ft_,
        IMintableERC20 xt_,
        IGearingToken gt_,
        TokenPairConfig memory config_
    ) external override {
        __initializeOwner(admin);
        if (address(collateral_) == address(underlying_)) revert CollateralCanNotEqualUnderlyinng();

        if (config_.openTime < block.timestamp || config_.maturity < config_.openTime)
            revert InvalidTime(config_.openTime, config_.maturity);

        underlying = underlying_;
        collateral = collateral_;
        _config = config_;
        ft = ft_;
        xt = xt_;
        gt = gt_;

        emit TokenPairInitialized(collateral, underlying, _config.openTime, _config.maturity, ft_, xt_, gt_);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function config() public view override returns (TokenPairConfig memory) {
        return _config;
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function tokens() external view override returns (IMintableERC20, IMintableERC20, IGearingToken, address, IERC20) {
        return (ft, xt, gt, collateral, underlying);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function updateTokenPairConfig(TokenPairConfig calldata newConfig) external override onlyOwner {
        TokenPairConfig memory mConfig = _config;
        if (newConfig.treasurer != mConfig.treasurer) {
            mConfig.treasurer = newConfig.treasurer;
            gt.setTreasurer(newConfig.treasurer);
        }
        mConfig.redeemFeeRatio = newConfig.redeemFeeRatio;
        mConfig.issueFtFeeRatio = newConfig.issueFtFeeRatio;

        _config = mConfig;
        emit UpdateTokenPairConfig(mConfig);
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity(uint maturity) internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    function mintFtAndXt(address receiver, uint256 underlyingAmt) external override nonReentrant isOpen {
        _mintFtAndXt(msg.sender, receiver, underlyingAmt);
    }

    function _mintFtAndXt(address caller, address receiver, uint256 underlyingAmt) internal {
        underlying.safeTransferFrom(caller, address(this), underlyingAmt);

        ft.mint(receiver, underlyingAmt);
        xt.mint(receiver, underlyingAmt);
    }

    function redeemFtAndXtToUnderlying(address receiver, uint256 underlyingAmt) external override nonReentrant isOpen {
        _redeemFtAndXtToUnderlying(msg.sender, receiver, underlyingAmt);
    }

    function _redeemFtAndXtToUnderlying(address caller, address receiver, uint256 underlyingAmt) internal {
        ft.safeTransferFrom(caller, address(this), underlyingAmt);
        xt.safeTransferFrom(caller, address(this), underlyingAmt);

        ft.burn(underlyingAmt);
        xt.burn(underlyingAmt);

        underlying.safeTransfer(receiver, underlyingAmt);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function leverageByXt(
        address receiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) external override nonReentrant isOpen returns (uint256 gtId) {
        return _leverageByXt(msg.sender, receiver, xtAmt, callbackData);
    }

    function _leverageByXt(
        address loanReceiver,
        address gtReceiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) internal returns (uint256 gtId) {
        xt.safeTransferFrom(loanReceiver, address(this), xtAmt);

        // 1 xt -> 1 underlying raised
        uint128 debt = xtAmt;

        // Send debt to borrower
        underlying.safeTransfer(loanReceiver, xtAmt);
        // Callback function
        bytes memory collateralData = IFlashLoanReceiver(loanReceiver).executeOperation(
            gtReceiver,
            underlying,
            xtAmt,
            callbackData
        );

        // Mint GT
        gtId = gt.mint(loanReceiver, gtReceiver, debt, collateralData);

        xt.burn(xtAmt);
        emit MintGt(loanReceiver, gtReceiver, gtId, debt, collateralData);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function issueFt(
        uint128 debt,
        bytes calldata collateralData
    ) external override nonReentrant isOpen returns (uint256 gtId, uint128 ftOutAmt) {
        return _issueFt(msg.sender, debt, collateralData);
    }

    function _issueFt(
        address caller,
        uint128 debt,
        bytes calldata collateralData
    ) internal returns (uint256 gtId, uint128 ftOutAmt) {
        // Mint GT
        gtId = gt.mint(caller, caller, debt, collateralData);

        TokenPairConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mConfig.issueFtFeeRatio) / Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(caller, ftOutAmt);

        emit IssueFt(caller, gtId, debt, ftOutAmt, issueFee, collateralData);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function issueFtByExistedGt(
        address receiver,
        uint128 debt,
        uint gtId
    ) external override nonReentrant isOpen returns (uint128 ftOutAmt) {
        return _issueFtByExistedGt(msg.sender, receiver, debt, gtId);
    }

    function _issueFtByExistedGt(
        address caller,
        address receiver,
        uint128 debt,
        uint gtId
    ) internal returns (uint128 ftOutAmt) {
        if (gt.ownerOf(gtId) != caller) revert TOBEDEFINED();
        gt.augmentDebt(gtId, debt);

        TokenPairConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mConfig.issueFtFeeRatio) / Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(receiver, ftOutAmt);

        emit IssueFtByExistedGt(caller, gtId, debt, ftOutAmt, issueFee);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function redeem(uint256 ftAmount) external virtual override nonReentrant {
        _redeem(msg.sender, ftAmount);
    }

    function _redeem(address caller, uint256 ftAmount) internal {
        TokenPairConfig memory mConfig = _config;
        {
            uint liquidationDeadline = gt.liquidatable()
                ? mConfig.maturity + Constants.LIQUIDATION_WINDOW
                : mConfig.maturity;
            if (block.timestamp < liquidationDeadline) {
                revert CanNotRedeemBeforeFinalLiquidationDeadline(liquidationDeadline);
            }
        }
        uint underlyingAmt;

        // The proportion that user will get how many underlying and collateral should be deliveried
        uint proportion = (ftAmount * Constants.DECIMAL_BASE_SQ) / ft.totalSupply();
        if (ftAmount > 0) {
            ft.safeTransferFrom(caller, address(this), ftAmount);
            ft.burn(ftAmount);
        }

        bytes memory deliveryData = gt.delivery(proportion, caller);
        // Transfer underlying output
        underlyingAmt += ((underlying.balanceOf(address(this))) * proportion) / Constants.DECIMAL_BASE_SQ;
        uint feeAmt;
        if (mConfig.redeemFeeRatio > 0) {
            feeAmt = (underlyingAmt * mConfig.redeemFeeRatio) / Constants.DECIMAL_BASE;
            underlying.safeTransfer(mConfig.treasurer, feeAmt);
            underlyingAmt -= feeAmt;
        }
        underlying.safeTransfer(caller, underlyingAmt);
        emit Redeem(caller, proportion.toUint128(), underlyingAmt.toUint128(), feeAmt.toUint128(), deliveryData);
    }

    /**
     * @inheritdoc ITermMaxTokenPair
     */
    function updateGtConfig(bytes memory configData) external override onlyOwner {
        gt.updateConfig(configData);
    }
}
