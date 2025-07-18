// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ITermMaxMarketV2} from "./ITermMaxMarketV2.sol";
import {IGearingToken} from "../v1/tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "../v1/IFlashLoanReceiver.sol";
import {ITermMaxOrder} from "../v1/ITermMaxOrder.sol";
import {Constants} from "../v1/lib/Constants.sol";
import {MarketConstantsV2} from "./lib/MarketConstantsV2.sol";
import {MarketErrors} from "../v1/errors/MarketErrors.sol";
import {MarketEvents} from "../v1/events/MarketEvents.sol";
import {StringUtil} from "../v1/lib/StringUtil.sol";
import {
    MarketConfig,
    MarketInitialParams,
    GtConfig,
    CurveCuts,
    FeeConfig,
    OrderConfig
} from "../v1/storage/TermMaxStorage.sol";
import {ISwapCallback} from "../v1/ISwapCallback.sol";
import {TransferUtilsV2} from "./lib/TransferUtilsV2.sol";
import {ITermMaxMarket, IMintableERC20, IERC20} from "../v1/ITermMaxMarket.sol";
import {IMintableERC20V2} from "./tokens/IMintableERC20V2.sol";
import {ITermMaxOrderV2} from "./ITermMaxOrderV2.sol";

/**
 * @title TermMax Market V2
 * @author Term Structure Labs
 */
contract TermMaxMarketV2 is
    ITermMaxMarket,
    ITermMaxMarketV2,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    MarketErrors,
    MarketEvents
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtilsV2 for IERC20;
    using TransferUtilsV2 for IMintableERC20;
    using StringUtil for string;
    using Math for *;

    address immutable MINTABLE_ERC20_IMPLEMENT;
    address immutable TERMMAX_ORDER_IMPLEMENT;

    MarketConfig private _config;
    address private collateral;
    IERC20 private debtToken;
    IMintableERC20 private ft;
    IMintableERC20 private xt;
    IGearingToken private gt;

    string public name;

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
    function initialize(MarketInitialParams memory params) external virtual override initializer {
        __Ownable_init_unchained(params.admin);
        __ReentrancyGuard_init_unchained();
        if (params.collateral == address(params.debtToken)) revert CollateralCanNotEqualUnderlyinng();
        MarketConfig memory config_ = params.marketConfig;
        if (config_.maturity <= block.timestamp) revert InvalidMaturity();
        _checkFee(config_.feeConfig);

        debtToken = params.debtToken;
        collateral = params.collateral;
        _config = config_;

        (ft, xt, gt) = _deployTokens(params);
        name = _contactString(MarketConstantsV2.PREFIX_MARKET, params.tokenName);
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
            MarketConstantsV2.PREFIX_FT.contact(params.tokenName),
            MarketConstantsV2.PREFIX_FT.contact(params.tokenSymbol),
            decimals
        );
        xt_.initialize(
            MarketConstantsV2.PREFIX_XT.contact(params.tokenName),
            MarketConstantsV2.PREFIX_XT.contact(params.tokenSymbol),
            decimals
        );
        gt_.initialize(
            MarketConstantsV2.PREFIX_GT.contact(params.tokenName),
            MarketConstantsV2.PREFIX_GT.contact(params.tokenSymbol),
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
    function tokens()
        external
        view
        virtual
        override
        returns (IMintableERC20, IMintableERC20, IGearingToken, address, IERC20)
    {
        return (ft, xt, IGearingToken(gt), collateral, debtToken);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateMarketConfig(MarketConfig calldata newConfig) external virtual override onlyOwner {
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

    function mint(address recipient, uint256 debtTokenAmt) external virtual override nonReentrant isOpen {
        _mint(msg.sender, recipient, debtTokenAmt);
    }

    function _mint(address caller, address recipient, uint256 debtTokenAmt) internal {
        debtToken.safeTransferFrom(caller, address(this), debtTokenAmt);

        ft.mint(recipient, debtTokenAmt);
        xt.mint(recipient, debtTokenAmt);

        emit Mint(caller, recipient, debtTokenAmt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function burn(address recipient, uint256 debtTokenAmt) external virtual override nonReentrant isOpen {
        _burn(msg.sender, msg.sender, recipient, debtTokenAmt);
    }

    /**
     * @inheritdoc ITermMaxMarketV2
     */
    function burn(address owner, address recipient, uint256 debtTokenAmt)
        external
        virtual
        override
        nonReentrant
        isOpen
    {
        _burn(owner, msg.sender, recipient, debtTokenAmt);
    }

    function _burn(address owner, address spender, address recipient, uint256 debtTokenAmt) internal {
        IMintableERC20V2(address(ft)).burn(owner, spender, debtTokenAmt);
        IMintableERC20V2(address(xt)).burn(owner, spender, debtTokenAmt);

        debtToken.safeTransfer(recipient, debtTokenAmt);

        emit Burn(owner, recipient, debtTokenAmt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function leverageByXt(address recipient, uint128 xtAmt, bytes calldata callbackData)
        external
        virtual
        override
        nonReentrant
        isOpen
        returns (uint256 gtId)
    {
        return _leverageByXt(msg.sender, msg.sender, recipient, xtAmt, callbackData);
    }

    /**
     * @inheritdoc ITermMaxMarketV2
     */
    function leverageByXt(address xtOwner, address recipient, uint128 xtAmt, bytes calldata callbackData)
        external
        virtual
        override
        nonReentrant
        isOpen
        returns (uint256 gtId)
    {
        return _leverageByXt(xtOwner, msg.sender, recipient, xtAmt, callbackData);
    }

    function _leverageByXt(
        address xtOwner,
        address loanReceiver,
        address gtReceiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) internal returns (uint256 gtId) {
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

        IMintableERC20V2(address(xt)).burn(xtOwner, msg.sender, xtAmt);
        emit LeverageByXt(loanReceiver, gtReceiver, gtId, debt, xtAmt, leverageFee, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function issueFt(address recipient, uint128 debt, bytes calldata collateralData)
        external
        virtual
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
        uint128 issueFee = debt.mulDiv(mintGtFeeRatio(), Constants.DECIMAL_BASE).toUint128();
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
        virtual
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
        uint128 issueFee = debt.mulDiv(mintGtFeeRatio(), Constants.DECIMAL_BASE).toUint128();
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
        virtual
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
        uint256 proportion =
            ftAmount.mulDiv(Constants.DECIMAL_BASE_SQ, (ft.totalSupply() - ft.balanceOf(address(this))));

        deliveryData = gt.previewDelivery(proportion);

        debtTokenAmt = debtToken.balanceOf(address(this)).mulDiv(proportion, Constants.DECIMAL_BASE_SQ);
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
        return _redeem(msg.sender, msg.sender, recipient, ftAmount);
    }

    /**
     * @inheritdoc ITermMaxMarketV2
     */
    function redeem(address ftOwner, address recipient, uint256 ftAmount)
        external
        virtual
        override
        nonReentrant
        returns (uint256, bytes memory)
    {
        return _redeem(ftOwner, msg.sender, recipient, ftAmount);
    }

    function _redeem(address ftOwner, address caller, address recipient, uint256 ftAmount)
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
        // burn ft reserves(from repayment or liquidation)
        uint256 ftReserve = ft.balanceOf(address(this));
        if (ftReserve > 0) {
            IMintableERC20V2(address(ft)).burn(address(this), address(this), ftReserve);
        }

        // The proportion that user will get how many debtToken and collateral should be deliveried
        uint256 proportion = ftAmount.mulDiv(Constants.DECIMAL_BASE_SQ, ft.totalSupply());

        // Burn ft
        IMintableERC20V2(address(ft)).burn(ftOwner, caller, ftAmount);

        deliveryData = gt.delivery(proportion, recipient);
        // Transfer debtToken output
        debtTokenAmt += debtToken.balanceOf(address(this)).mulDiv(proportion, Constants.DECIMAL_BASE_SQ);
        debtToken.safeTransfer(recipient, debtTokenAmt);
        emit Redeem(caller, recipient, proportion.toUint128(), debtTokenAmt.toUint128(), deliveryData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateGtConfig(bytes memory configData) external virtual override onlyOwner {
        gt.updateConfig(configData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function createOrder(address maker, uint256 maxXtReserve, ISwapCallback swapTrigger, CurveCuts memory curveCuts)
        external
        virtual
        nonReentrant
        isOpen
        returns (ITermMaxOrder)
    {
        OrderConfig memory orderconfig;
        orderconfig.maxXtReserve = maxXtReserve;
        orderconfig.swapTrigger = swapTrigger;
        orderconfig.curveCuts = curveCuts;
        return _createOrder(maker, orderconfig);
    }

    /**
     * @inheritdoc ITermMaxMarketV2
     */
    function createOrder(address maker, OrderConfig memory orderconfig) external returns (ITermMaxOrder) {
        return _createOrder(maker, orderconfig);
    }

    function _createOrder(address maker, OrderConfig memory orderconfig) internal returns (ITermMaxOrder) {
        address order = Clones.clone(TERMMAX_ORDER_IMPLEMENT);
        ITermMaxOrderV2(order).initialize(maker, [ft, xt, debtToken], gt, orderconfig, _config);
        emit CreateOrder(maker, ITermMaxOrder(order));
        return ITermMaxOrder(order);
    }

    function updateOrderFeeRate(ITermMaxOrder order, FeeConfig memory newFeeConfig) external virtual onlyOwner {
        _checkFee(newFeeConfig);
        order.updateFeeConfig(newFeeConfig);
    }
}
