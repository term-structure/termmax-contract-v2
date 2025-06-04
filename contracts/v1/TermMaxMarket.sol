// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ITermMaxMarket, IMintableERC20, IERC20} from "./ITermMaxMarket.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {ITermMaxOrder} from "./ITermMaxOrder.sol";
import {Constants} from "./lib/Constants.sol";
import {MarketConstants} from "./lib/MarketConstants.sol";
import {MarketErrors} from "./errors/MarketErrors.sol";
import {MarketEvents} from "./events/MarketEvents.sol";
import {StringUtil} from "./lib/StringUtil.sol";
import {MarketConfig, MarketInitialParams, GtConfig, CurveCuts, FeeConfig} from "./storage/TermMaxStorage.sol";
import {ISwapCallback} from "./ISwapCallback.sol";
import {TransferUtils} from "./lib/TransferUtils.sol";

/**
 * @title TermMax Market
 * @author Term Structure Labs
 */
contract TermMaxMarket is
    ITermMaxMarket,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    MarketErrors,
    MarketEvents
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IMintableERC20;
    using StringUtil for string;

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
        if (block.timestamp >= _config.maturity) {
            revert TermIsNotOpen();
        }
        _;
    }

    constructor(address MINTABLE_ERC20_IMPLEMENT_, address TERMMAX_ORDER_IMPLEMENT_) {
        MINTABLE_ERC20_IMPLEMENT = MINTABLE_ERC20_IMPLEMENT_;
        TERMMAX_ORDER_IMPLEMENT = TERMMAX_ORDER_IMPLEMENT_;
        _disableInitializers();
    }

    function mintGtFeeRatio() public view override returns (uint256) {
        uint256 daysToMaturity = _daysToMaturity(_config.maturity);
        return (daysToMaturity * uint256(_config.feeConfig.mintGtFeeRatio) * uint256(_config.feeConfig.mintGtFeeRef))
            / (Constants.DAYS_IN_YEAR * Constants.DECIMAL_BASE + uint256(_config.feeConfig.mintGtFeeRef) * daysToMaturity);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function initialize(MarketInitialParams memory params) external override initializer {
        __Ownable_init(params.admin);
        __ReentrancyGuard_init();
        if (params.collateral == address(params.debtToken)) revert CollateralCanNotEqualUnderlyinng();
        MarketConfig memory config_ = params.marketConfig;
        if (config_.maturity <= block.timestamp) revert InvalidMaturity();
        _checkFee(config_.feeConfig);

        debtToken = params.debtToken;
        collateral = params.collateral;
        _config = config_;

        (ft, xt, gt) = _deployTokens(params);

        emit MarketInitialized(params.collateral, params.debtToken, _config.maturity, ft, xt, gt);
    }

    function _deployTokens(MarketInitialParams memory params)
        internal
        returns (IMintableERC20 ft_, IMintableERC20 xt_, IGearingToken gt_)
    {
        ft_ = IMintableERC20(Clones.clone(MINTABLE_ERC20_IMPLEMENT));
        xt_ = IMintableERC20(Clones.clone(MINTABLE_ERC20_IMPLEMENT));
        gt_ = IGearingToken(Clones.clone(params.gtImplementation));
        uint8 decimals = params.debtToken.decimals();
        ft_.initialize(
            MarketConstants.PREFIX_FT.contact(params.tokenName),
            MarketConstants.PREFIX_FT.contact(params.tokenSymbol),
            decimals
        );
        xt_.initialize(
            MarketConstants.PREFIX_XT.contact(params.tokenName),
            MarketConstants.PREFIX_XT.contact(params.tokenSymbol),
            decimals
        );
        gt_.initialize(
            MarketConstants.PREFIX_GT.contact(params.tokenName),
            MarketConstants.PREFIX_GT.contact(params.tokenSymbol),
            GtConfig(
                params.collateral,
                params.debtToken,
                ft_,
                params.marketConfig.treasurer,
                params.marketConfig.maturity,
                params.loanConfig
            ),
            params.gtInitalParams
        );
    }

    function _contactString(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
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
        _checkFee(newConfig.feeConfig);
        mConfig.feeConfig = newConfig.feeConfig;

        _config = mConfig;
        emit UpdateMarketConfig(mConfig);
    }

    function _checkFee(FeeConfig memory fee) internal pure {
        if (
            fee.borrowTakerFeeRatio >= Constants.MAX_FEE_RATIO || fee.borrowMakerFeeRatio >= Constants.MAX_FEE_RATIO
                || fee.lendTakerFeeRatio >= Constants.MAX_FEE_RATIO || fee.lendMakerFeeRatio >= Constants.MAX_FEE_RATIO
                || fee.mintGtFeeRatio >= Constants.MAX_FEE_RATIO || fee.mintGtFeeRef > 5 * Constants.DECIMAL_BASE
        ) revert FeeTooHigh();
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity(uint256 maturity) internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    function mint(address recipient, uint256 debtTokenAmt) external override nonReentrant isOpen {
        _mint(msg.sender, recipient, debtTokenAmt);
    }

    function _mint(address caller, address recipient, uint256 debtTokenAmt) internal {
        debtToken.safeTransferFrom(caller, address(this), debtTokenAmt);

        ft.mint(recipient, debtTokenAmt);
        xt.mint(recipient, debtTokenAmt);

        emit Mint(caller, recipient, debtTokenAmt);
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

        emit Burn(caller, recipient, debtTokenAmt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function leverageByXt(address recipient, uint128 xtAmt, bytes calldata callbackData)
        external
        override
        nonReentrant
        isOpen
        returns (uint256 gtId)
    {
        return _leverageByXt(msg.sender, recipient, xtAmt, callbackData);
    }

    function _leverageByXt(address loanReceiver, address gtReceiver, uint128 xtAmt, bytes calldata callbackData)
        internal
        returns (uint256 gtId)
    {
        xt.safeTransferFrom(loanReceiver, address(this), xtAmt);

        // Send debt to borrower
        debtToken.safeTransfer(loanReceiver, xtAmt);
        // Callback function
        bytes memory collateralData =
            IFlashLoanReceiver(loanReceiver).executeOperation(gtReceiver, debtToken, xtAmt, callbackData);

        uint128 debt = ((xtAmt * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - mintGtFeeRatio())).toUint128();

        MarketConfig memory mConfig = _config;
        uint128 leverageFee = debt - xtAmt;
        ft.mint(mConfig.treasurer, leverageFee);

        // Mint GT
        gtId = gt.mint(loanReceiver, gtReceiver, debt, collateralData);

        xt.burn(xtAmt);
        emit LeverageByXt(loanReceiver, gtReceiver, gtId, debt, xtAmt, leverageFee, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function issueFt(address recipient, uint128 debt, bytes calldata collateralData)
        external
        override
        nonReentrant
        isOpen
        returns (uint256 gtId, uint128 ftOutAmt)
    {
        return _issueFt(msg.sender, recipient, debt, collateralData);
    }

    function _issueFt(address caller, address recipient, uint128 debt, bytes calldata collateralData)
        internal
        returns (uint256 gtId, uint128 ftOutAmt)
    {
        // Mint GT
        gtId = gt.mint(caller, recipient, debt, collateralData);

        MarketConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mintGtFeeRatio()) / Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(recipient, ftOutAmt);

        emit IssueFt(caller, recipient, gtId, debt, ftOutAmt, issueFee, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function issueFtByExistedGt(address recipient, uint128 debt, uint256 gtId)
        external
        override
        nonReentrant
        isOpen
        returns (uint128 ftOutAmt)
    {
        return _issueFtByExistedGt(msg.sender, recipient, debt, gtId);
    }

    function _issueFtByExistedGt(address caller, address recipient, uint128 debt, uint256 gtId)
        internal
        returns (uint128 ftOutAmt)
    {
        gt.augmentDebt(caller, gtId, debt);

        MarketConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mintGtFeeRatio()) / Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(recipient, ftOutAmt);

        emit IssueFtByExistedGt(caller, recipient, gtId, debt, ftOutAmt, issueFee);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function previewRedeem(uint256 ftAmount)
        external
        view
        override
        returns (uint256 debtTokenAmt, bytes memory deliveryData)
    {
        MarketConfig memory mConfig = _config;
        {
            uint256 liquidationDeadline =
                gt.liquidatable() ? mConfig.maturity + Constants.LIQUIDATION_WINDOW : mConfig.maturity;
            if (block.timestamp < liquidationDeadline) {
                revert CanNotRedeemBeforeFinalLiquidationDeadline(liquidationDeadline);
            }
        }

        // The proportion that user will get how many debtToken and collateral should be deliveried
        uint256 proportion = (ftAmount * Constants.DECIMAL_BASE_SQ) / (ft.totalSupply() - ft.balanceOf(address(this)));

        deliveryData = gt.previewDelivery(proportion);

        debtTokenAmt = ((debtToken.balanceOf(address(this))) * proportion) / Constants.DECIMAL_BASE_SQ;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function redeem(uint256 ftAmount, address recipient)
        external
        virtual
        override
        nonReentrant
        returns (uint256, bytes memory)
    {
        return _redeem(msg.sender, recipient, ftAmount);
    }

    function _redeem(address caller, address recipient, uint256 ftAmount)
        internal
        returns (uint256 debtTokenAmt, bytes memory deliveryData)
    {
        MarketConfig memory mConfig = _config;
        {
            uint256 liquidationDeadline =
                gt.liquidatable() ? mConfig.maturity + Constants.LIQUIDATION_WINDOW : mConfig.maturity;
            if (block.timestamp < liquidationDeadline) {
                revert CanNotRedeemBeforeFinalLiquidationDeadline(liquidationDeadline);
            }
        }

        // Burn ft reserves
        ft.burn(ft.balanceOf(address(this)));

        ft.safeTransferFrom(caller, address(this), ftAmount);

        // The proportion that user will get how many debtToken and collateral should be deliveried
        uint256 proportion = (ftAmount * Constants.DECIMAL_BASE_SQ) / ft.totalSupply();

        deliveryData = gt.delivery(proportion, recipient);
        // Transfer debtToken output
        debtTokenAmt += ((debtToken.balanceOf(address(this))) * proportion) / Constants.DECIMAL_BASE_SQ;
        debtToken.safeTransfer(recipient, debtTokenAmt);
        emit Redeem(caller, recipient, proportion.toUint128(), debtTokenAmt.toUint128(), deliveryData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateGtConfig(bytes memory configData) external override onlyOwner {
        gt.updateConfig(configData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function createOrder(address maker, uint256 maxXtReserve, ISwapCallback swapTrigger, CurveCuts memory curveCuts)
        external
        nonReentrant
        isOpen
        returns (ITermMaxOrder order)
    {
        order = ITermMaxOrder(Clones.clone(TERMMAX_ORDER_IMPLEMENT));
        order.initialize(maker, [ft, xt, debtToken], gt, maxXtReserve, swapTrigger, curveCuts, _config);
        emit CreateOrder(maker, order);
    }

    function updateOrderFeeRate(ITermMaxOrder order, FeeConfig memory newFeeConfig) external onlyOwner {
        _checkFee(newFeeConfig);
        order.updateFeeConfig(newFeeConfig);
    }
}
