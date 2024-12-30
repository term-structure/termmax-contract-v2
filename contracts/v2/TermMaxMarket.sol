// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITermMaxMarket, MarketConfig, IMintableERC20, IERC20} from "./ITermMaxMarket.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {Constants} from "./lib/Constants.sol";
import {Ownable} from "./access/Ownable.sol";
import {MarketErrors} from "./errors/MarketErrors.sol";
import {MarketEvents} from "./events/MarketEvents.sol";

/**
 * @title TermMax Market
 * @author Term Structure Labs
 */
contract TermMaxMarket is ITermMaxMarket, ReentrancyGuard, Ownable, Pausable, MarketErrors, MarketEvents {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;

    address immutable MINTABLE_ERC20_IMPLEMENT;
    address immutable TERMMAX_ORDER_IMPLEMENT;

    MarketConfig private _config;
    address private collateral;
    IERC20 private debtToken;
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
     * @inheritdoc ITermMaxMarket
     */
    function initialize(
        address admin,
        address collateral_,
        IERC20 debtToken_,
        IMintableERC20 ft_,
        IMintableERC20 xt_,
        IGearingToken gt_,
        MarketConfig memory config_
    ) external override {
        __initializeOwner(admin);
        if (address(collateral_) == address(debtToken_)) revert CollateralCanNotEqualUnderlyinng();

        if (config_.openTime < block.timestamp || config_.maturity < config_.openTime)
            revert InvalidTime(config_.openTime, config_.maturity);
        _checkFee(config_.feeConfig.borrowFeeRatio);
        _checkFee(config_.feeConfig.lendFeeRatio);
        _checkFee(config_.feeConfig.redeemFeeRatio);
        _checkFee(config_.feeConfig.issueFtFeeRatio);
        _checkFee(config_.feeConfig.minNBorrowFeeR);
        _checkFee(config_.feeConfig.minNLendFeeR);

        debtToken = debtToken_;
        collateral = collateral_;
        _config = config_;
        ft = ft_;
        xt = xt_;
        gt = gt_;

        emit MarketInitialized(collateral, debtToken, _config.openTime, _config.maturity, ft_, xt_, gt_);
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
    function tokens() external view override returns (IMintableERC20, IMintableERC20, IGearingToken, address, IERC20) {
        return (ft, xt, gt, collateral, debtToken);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateMarketConfig(MarketConfig calldata newConfig) external override onlyOwner {
        MarketConfig memory mConfig = _config;
        if (newConfig.treasurer != mConfig.treasurer) {
            mConfig.treasurer = newConfig.treasurer;
            gt.setTreasurer(newConfig.treasurer);
        }
        _checkFee(newConfig.feeConfig.borrowFeeRatio);
        _checkFee(newConfig.feeConfig.lendFeeRatio);
        _checkFee(newConfig.feeConfig.redeemFeeRatio);
        _checkFee(newConfig.feeConfig.issueFtFeeRatio);
        _checkFee(newConfig.feeConfig.minNBorrowFeeR);
        _checkFee(newConfig.feeConfig.minNLendFeeR);

        mConfig.feeConfig = newConfig.feeConfig;

        _config = mConfig;
        emit UpdateMarketConfig(mConfig);
    }

    function _checkFee(uint32 feeRatio) internal pure {
        if (feeRatio >= Constants.MAX_FEE_RATIO) revert FeeTooHigh();
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity(uint maturity) internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    function mint(address recipient, uint256 debtTokenAmt) external override nonReentrant isOpen {
        _mint(msg.sender, recipient, debtTokenAmt);
    }

    function _mint(address caller, address recipient, uint256 debtTokenAmt) internal {
        debtToken.safeTransferFrom(caller, address(this), debtTokenAmt);

        ft.mint(recipient, debtTokenAmt);
        xt.mint(recipient, debtTokenAmt);
    }

    function burn(address recipient, uint256 debtTokenAmt) external override nonReentrant isOpen {
        _burn(msg.sender, recipient, debtTokenAmt);
    }

    function _burn(address caller, address recipient, uint256 debtTokenAmt) internal {
        ft.safeTransferFrom(caller, address(this), debtTokenAmt);
        xt.safeTransferFrom(caller, address(this), debtTokenAmt);

        ft.burn(debtTokenAmt);
        xt.burn(debtTokenAmt);

        debtToken.safeTransfer(recipient, debtTokenAmt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function leverageByXt(
        address recipient,
        uint128 xtAmt,
        bytes calldata callbackData
    ) external override nonReentrant isOpen returns (uint256 gtId) {
        return _leverageByXt(msg.sender, recipient, xtAmt, callbackData);
    }

    function _leverageByXt(
        address loanReceiver,
        address gtReceiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) internal returns (uint256 gtId) {
        xt.safeTransferFrom(loanReceiver, address(this), xtAmt);

        // 1 xt -> 1 debtToken raised
        uint128 debt = xtAmt;

        // Send debt to borrower
        debtToken.safeTransfer(loanReceiver, xtAmt);
        // Callback function
        bytes memory collateralData = IFlashLoanReceiver(loanReceiver).executeOperation(
            gtReceiver,
            debtToken,
            xtAmt,
            callbackData
        );

        // Mint GT
        gtId = gt.mint(loanReceiver, gtReceiver, debt, collateralData);

        xt.burn(xtAmt);
        emit MintGt(loanReceiver, gtReceiver, gtId, debt, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function issueFt(
        address recipient,
        uint128 debt,
        bytes calldata collateralData
    ) external override nonReentrant isOpen returns (uint256 gtId, uint128 ftOutAmt) {
        return _issueFt(msg.sender, recipient, debt, collateralData);
    }

    function _issueFt(
        address caller,
        address recipient,
        uint128 debt,
        bytes calldata collateralData
    ) internal returns (uint256 gtId, uint128 ftOutAmt) {
        // Mint GT
        gtId = gt.mint(caller, recipient, debt, collateralData);

        MarketConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mConfig.feeConfig.issueFtFeeRatio) / Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(recipient, ftOutAmt);

        emit IssueFt(caller, recipient, gtId, debt, ftOutAmt, issueFee, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function issueFtByExistedGt(
        address recipient,
        uint128 debt,
        uint gtId
    ) external override nonReentrant isOpen returns (uint128 ftOutAmt) {
        return _issueFtByExistedGt(msg.sender, recipient, debt, gtId);
    }

    function _issueFtByExistedGt(
        address caller,
        address recipient,
        uint128 debt,
        uint gtId
    ) internal returns (uint128 ftOutAmt) {
        gt.augmentDebt(caller, gtId, debt);

        MarketConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mConfig.feeConfig.issueFtFeeRatio) / Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(recipient, ftOutAmt);

        emit IssueFtByExistedGt(caller, recipient, gtId, debt, ftOutAmt, issueFee);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function redeem(uint256 ftAmount, address recipient) external virtual override nonReentrant {
        _redeem(msg.sender, recipient, ftAmount);
    }

    function _redeem(address caller, address recipient, uint256 ftAmount) internal {
        MarketConfig memory mConfig = _config;
        {
            uint liquidationDeadline = gt.liquidatable()
                ? mConfig.maturity + Constants.LIQUIDATION_WINDOW
                : mConfig.maturity;
            if (block.timestamp < liquidationDeadline) {
                revert CanNotRedeemBeforeFinalLiquidationDeadline(liquidationDeadline);
            }
        }

        // Burn ft reserves
        ft.burn(ft.balanceOf(address(this)));

        uint debtTokenAmt;

        // The proportion that user will get how many debtToken and collateral should be deliveried
        uint proportion = (ftAmount * Constants.DECIMAL_BASE_SQ) / ft.totalSupply();
        if (ftAmount > 0) {
            ft.safeTransferFrom(caller, address(this), ftAmount);
        }

        bytes memory deliveryData = gt.delivery(proportion, caller);
        // Transfer debtToken output
        debtTokenAmt += ((debtToken.balanceOf(address(this))) * proportion) / Constants.DECIMAL_BASE_SQ;
        uint feeAmt;
        if (mConfig.feeConfig.redeemFeeRatio > 0) {
            feeAmt = (debtTokenAmt * mConfig.feeConfig.redeemFeeRatio) / Constants.DECIMAL_BASE;
            debtToken.safeTransfer(mConfig.treasurer, feeAmt);
            debtTokenAmt -= feeAmt;
        }
        debtToken.safeTransfer(recipient, debtTokenAmt);
        emit Redeem(
            caller,
            recipient,
            proportion.toUint128(),
            debtTokenAmt.toUint128(),
            feeAmt.toUint128(),
            deliveryData
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateGtConfig(bytes memory configData) external override onlyOwner {
        gt.updateConfig(configData);
    }
}
