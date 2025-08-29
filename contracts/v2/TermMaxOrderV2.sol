// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {
    OwnableUpgradeable,
    Ownable2StepUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ITermMaxOrder, IERC20} from "../v1/ITermMaxOrder.sol";
import {ITermMaxMarket} from "../v1/ITermMaxMarket.sol";
import {IGearingToken} from "../v1/tokens/IGearingToken.sol";
import {Constants} from "../v1/lib/Constants.sol";
import {TermMaxCurve, MathLib} from "../v1/lib/TermMaxCurve.sol";
import {OrderErrors} from "../v1/errors/OrderErrors.sol";
import {OrderEvents} from "../v1/events/OrderEvents.sol";
import {OrderConfig, MarketConfig, CurveCuts, CurveCut, FeeConfig} from "../v1/storage/TermMaxStorage.sol";
import {ISwapCallback} from "../v1/ISwapCallback.sol";
import {TransferUtils} from "../v1/lib/TransferUtils.sol";
import {ITermMaxOrderV2, OrderInitialParams} from "./ITermMaxOrderV2.sol";
import {OrderEventsV2} from "./events/OrderEventsV2.sol";
import {OrderErrorsV2} from "./errors/OrderErrorsV2.sol";
import {VersionV2} from "./VersionV2.sol";

/**
 * @title TermMax Order V2
 * @notice Support deposit idle funds to the pool to earn yield
 * @author Term Structure Labs
 */
contract TermMaxOrderV2 is
    ITermMaxOrder,
    ITermMaxOrderV2,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    OrderErrors,
    OrderEvents,
    VersionV2
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;
    using TransferUtils for IERC4626;
    using MathLib for *;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    ITermMaxMarket public market;

    IERC20 private ft;
    IERC20 private xt;
    IERC20 private debtToken;
    IGearingToken private gt;

    OrderConfig private _orderConfig;

    uint64 private maturity;

    /// @notice The virtual xt reserve can present current price, which only changed when swap happens
    uint256 public virtualXtReserve;
    IERC4626 public pool;

    // =============================================================================
    // MODIFIERS
    // =============================================================================

    /// @notice Check if the market is borrowing allowed
    modifier onlyBorrowingIsAllowed(OrderConfig memory config) {
        if (config.curveCuts.lendCurveCuts.length == 0) {
            revert BorrowIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier onlyLendingIsAllowed(OrderConfig memory config) {
        if (config.curveCuts.borrowCurveCuts.length == 0) {
            revert LendIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the order is tradable
    modifier isOpen() {
        _requireNotPaused();
        if (block.timestamp >= maturity) {
            revert TermIsNotOpen();
        }
        _;
    }

    modifier onlyMarket() {
        if (msg.sender != address(market)) revert OnlyMarket();
        _;
    }

    // =============================================================================
    // CONSTRUCTOR & INITIALIZATION
    // =============================================================================

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the order with V1 parameters (deprecated)
     * @inheritdoc ITermMaxOrder
     */
    function initialize(
        address,
        IERC20[3] memory,
        IGearingToken,
        uint256,
        ISwapCallback,
        CurveCuts memory,
        MarketConfig memory
    ) external virtual override initializer {
        revert OrderErrorsV2.UseOrderInitializationFunctionV2();
    }

    /**
     * @notice Initialize the order with V2 parameters
     * @inheritdoc ITermMaxOrderV2
     */
    function initialize(OrderInitialParams memory params) external virtual override initializer {
        __Ownable_init_unchained(params.maker);
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
        address _market = _msgSender();
        market = ITermMaxMarket(_market);
        maturity = params.maturity;
        ft = params.ft;
        xt = params.xt;
        debtToken = params.debtToken;
        gt = params.gt;
        _setPool(params.pool);
        _updateCurve(params.orderConfig.curveCuts);
        _updateGeneralConfig(
            params.orderConfig.gtId,
            params.orderConfig.maxXtReserve,
            params.orderConfig.swapTrigger,
            params.virtualXtReserve
        );
        emit OrderEventsV2.OrderInitialized(params.maker, _market);
    }

    // =============================================================================
    // VIEW FUNCTIONS - STATE GETTERS
    // =============================================================================

    /**
     * @notice Get the maker (owner) of the order
     * @return The maker address
     */
    function maker() public view returns (address) {
        return owner();
    }

    /**
     * @notice Get the current order configuration
     * @inheritdoc ITermMaxOrder
     * @return The current order configuration
     */
    function orderConfig() external view virtual returns (OrderConfig memory) {
        return _orderConfig;
    }

    /**
     * @notice Get the token reserves (FT and XT balances)
     * @inheritdoc ITermMaxOrder
     * @return FT balance, XT balance
     */
    function tokenReserves() public view override returns (uint256, uint256) {
        return (ft.balanceOf(address(this)), xt.balanceOf(address(this)));
    }

    /**
     * @notice Get real reserves including assets in pool
     * @return ftReserve FT reserve including pool assets
     * @return xtReserve XT reserve including pool assets
     */
    function getRealReserves() external view virtual returns (uint256 ftReserve, uint256 xtReserve) {
        uint256 assetsInPool = _assetsInPool();
        ftReserve = ft.balanceOf(address(this)) + assetsInPool;
        xtReserve = xt.balanceOf(address(this)) + assetsInPool;
    }

    /**
     * @notice Calculate current APR for lending and borrowing
     * @inheritdoc ITermMaxOrder
     * @return lendApr_ Current lending APR
     * @return borrowApr_ Current borrowing APR
     */
    function apr() external view virtual override returns (uint256 lendApr_, uint256 borrowApr_) {
        uint256 daysToMaturity = _daysToMaturity();
        uint256 oriXtReserve = xt.balanceOf(address(this));

        CurveCuts memory curveCuts = _orderConfig.curveCuts;
        if (curveCuts.lendCurveCuts.length == 0) {
            lendApr_ = 0;
        } else {
            uint256 lendCutId = TermMaxCurve.calcCutId(curveCuts.lendCurveCuts, oriXtReserve);
            (, uint256 lendVXtReserve, uint256 lendVFtReserve) = TermMaxCurve.calcIntervalProps(
                Constants.DECIMAL_BASE, daysToMaturity, curveCuts.lendCurveCuts[lendCutId], oriXtReserve
            );
            lendApr_ =
                ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / (lendVXtReserve * daysToMaturity));
        }
        if (curveCuts.borrowCurveCuts.length == 0) {
            borrowApr_ = type(uint256).max;
        } else {
            uint256 borrowCutId = TermMaxCurve.calcCutId(curveCuts.borrowCurveCuts, oriXtReserve);
            (, uint256 borrowVXtReserve, uint256 borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
                Constants.DECIMAL_BASE, daysToMaturity, curveCuts.borrowCurveCuts[borrowCutId], oriXtReserve
            );

            borrowApr_ = (
                (borrowVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR)
                    / (borrowVXtReserve * daysToMaturity)
            );
        }
    }

    // =============================================================================
    // INTERNAL VIEW FUNCTIONS - HELPERS
    // =============================================================================

    /**
     * @notice Get assets amount in the staking pool
     * @return assets Amount of assets in pool
     */
    function _assetsInPool() internal view returns (uint256 assets) {
        if (pool != IERC4626(address(0))) {
            assets = pool.convertToAssets(pool.balanceOf(address(this)));
        }
    }

    /**
     * @notice Calculate days until maturity
     * @return daysToMaturity Number of days to maturity
     */
    function _daysToMaturity() internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    // =============================================================================
    // ADMIN FUNCTIONS - CONFIGURATION
    // =============================================================================

    /**
     * @notice Update order configuration and token amounts
     * @inheritdoc ITermMaxOrder
     * @param newOrderConfig New order configuration
     * @param ftChangeAmt Change in FT amount (positive = deposit, negative = withdraw)
     * @param xtChangeAmt Change in XT amount (positive = deposit, negative = withdraw)
     */
    function updateOrder(OrderConfig memory newOrderConfig, int256 ftChangeAmt, int256 xtChangeAmt)
        external
        virtual
        override
        onlyOwner
    {
        _updateCurve(newOrderConfig.curveCuts);
        if (ftChangeAmt > 0) {
            ft.safeTransferFrom(msg.sender, address(this), ftChangeAmt.toUint256());
        } else if (ftChangeAmt < 0) {
            ft.safeTransfer(msg.sender, (-ftChangeAmt).toUint256());
        }
        if (xtChangeAmt > 0) {
            xt.safeTransferFrom(msg.sender, address(this), xtChangeAmt.toUint256());
        } else if (xtChangeAmt < 0) {
            xt.safeTransfer(msg.sender, (-xtChangeAmt).toUint256());
        }
        _orderConfig.maxXtReserve = newOrderConfig.maxXtReserve;
        _orderConfig.gtId = newOrderConfig.gtId;
        _orderConfig.swapTrigger = newOrderConfig.swapTrigger;
        emit UpdateOrder(
            newOrderConfig.curveCuts,
            ftChangeAmt,
            xtChangeAmt,
            newOrderConfig.gtId,
            newOrderConfig.maxXtReserve,
            newOrderConfig.swapTrigger
        );
    }

    /**
     * @notice Set curve configuration
     * @param newCurveCuts New curve cuts configuration
     */
    function setCurve(CurveCuts memory newCurveCuts) external virtual onlyOwner {
        _updateCurve(newCurveCuts);
    }

    function setGeneralConfig(uint256 gtId, uint256 maxXtReserve, ISwapCallback swapTrigger, uint256 virtualXtReserve_)
        external
        virtual
        onlyOwner
    {
        _updateGeneralConfig(gtId, maxXtReserve, swapTrigger, virtualXtReserve_);
    }

    function setPool(IERC4626 newPool) external virtual onlyOwner {
        _setPool(newPool);
    }

    function _setPool(IERC4626 newPool) internal {
        IERC4626 oldPool = pool;
        uint256 debtTokenAmt;
        if (address(oldPool) != address(0)) {
            // Withdraw all assets from the old pool
            uint256 shares = oldPool.balanceOf(address(this));
            if (shares != 0) {
                debtTokenAmt = oldPool.redeem(shares, address(this), address(this));
            }
        }
        if (address(newPool) != address(0)) {
            uint256 ftBalance = ft.balanceOf(address(this));
            uint256 xtBalance = xt.balanceOf(address(this));
            uint256 maxBurned = ftBalance > xtBalance ? xtBalance : ftBalance;
            if (maxBurned != 0) {
                ITermMaxMarket _market = market;
                _market.burn(address(this), maxBurned);
                debtTokenAmt += maxBurned;
            }
            if (debtTokenAmt != 0) {
                // If new pool is set, deposit all debt token to the new pool
                debtToken.safeIncreaseAllowance(address(newPool), debtTokenAmt);
                newPool.deposit(debtTokenAmt, address(this));
            }
        } else if (debtTokenAmt != 0) {
            ITermMaxMarket _market = market;
            debtToken.safeIncreaseAllowance(address(_market), debtTokenAmt);
            _market.mint(address(this), debtTokenAmt);
        }
        pool = newPool;
        emit OrderEventsV2.PoolUpdated(address(newPool));
    }

    /**
     * @notice Update fee configuration (only callable by market)
     * @inheritdoc ITermMaxOrder
     * @param newFeeConfig New fee configuration
     */
    function updateFeeConfig(FeeConfig memory newFeeConfig) external virtual override onlyMarket {
        revert OrderErrorsV2.FeeConfigCanNotBeUpdated();
    }

    /**
     * @notice Internal function to update general configuration
     * @param gtId Gearing token ID
     * @param maxXtReserve Maximum XT reserve
     * @param swapTrigger Swap callback trigger
     * @param virtualXtReserve_ Virtual XT reserve
     */
    function _updateGeneralConfig(
        uint256 gtId,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger,
        uint256 virtualXtReserve_
    ) internal {
        _orderConfig.gtId = gtId;
        _orderConfig.maxXtReserve = maxXtReserve;
        _orderConfig.swapTrigger = swapTrigger;
        virtualXtReserve = virtualXtReserve_;
        emit OrderEventsV2.GeneralConfigUpdated(gtId, maxXtReserve, swapTrigger, virtualXtReserve_);
    }

    /**
     * @notice Pause the order
     * @inheritdoc ITermMaxOrder
     */
    function pause() external virtual override onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the order
     * @inheritdoc ITermMaxOrder
     */
    function unpause() external virtual override onlyOwner {
        _unpause();
    }

    // =============================================================================
    // LIQUIDITY MANAGEMENT FUNCTIONS
    // =============================================================================

    function addLiquidity(IERC20 asset, uint256 amount) external nonReentrant onlyOwner {
        _addLiquidity(asset, amount);
    }

    function removeLiquidity(IERC20 asset, uint256 amount, address recipient) external nonReentrant onlyOwner {
        _removeLiquidity(asset, amount, recipient);
    }

    function _addLiquidity(IERC20 asset, uint256 amount) internal {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        IERC4626 _pool = pool;
        ITermMaxMarket _market = market;
        IERC20 _debtToken = debtToken;
        if (address(_pool) == address(0) && asset == _debtToken) {
            // mint debt toke to ft and xt if pool is not set
            _debtToken.safeIncreaseAllowance(address(_market), amount);
            _market.mint(address(this), amount);
        } else if (address(_pool) != address(0) && asset == _debtToken) {
            // burn ft and xt to debt token and deposit to pool
            uint256 ftBalance = ft.balanceOf(address(this));
            uint256 xtBalance = xt.balanceOf(address(this));
            uint256 maxBurned = ftBalance > xtBalance ? xtBalance : ftBalance;
            if (maxBurned != 0) {
                _market.burn(address(this), maxBurned);
            }
            // if pool is set and asset is debt token, deposit to get shares
            amount += maxBurned;
            asset.safeIncreaseAllowance(address(_pool), amount);
            _pool.deposit(amount, address(this));
        }
    }

    function _removeLiquidity(IERC20 asset, uint256 amount, address recipient) internal {
        IERC4626 _pool = pool;
        ITermMaxMarket _market = market;
        IERC20 _debtToken = debtToken;
        if (address(_pool) == address(0) && asset == _debtToken) {
            // if pool is not set, always burn ft and xt to recipient
            _market.burn(recipient, amount);
        } else if (address(_pool) != address(0)) {
            uint256 ftBalance = ft.balanceOf(address(this));
            uint256 xtBalance = xt.balanceOf(address(this));
            uint256 maxBurned = ftBalance > xtBalance ? xtBalance : ftBalance;

            if (asset == _debtToken) {
                if (maxBurned >= amount) {
                    // if enough ft and xt, burn to debt token
                    _market.burn(recipient, amount);
                } else {
                    // if not enough ft and xt, burn all and withdraw from pool
                    _market.burn(recipient, maxBurned);
                    _pool.withdraw(amount - maxBurned, recipient, address(this));
                }
            } else {
                // transform ft and xt to debt token and deposit to pool
                _market.burn(recipient, maxBurned);
                _pool.deposit(maxBurned, address(this));
                // transfer shares to recipient
                _pool.safeTransfer(recipient, amount);
            }
        }
    }

    /**
     * @notice Withdraw assets from the contract
     * @param token Token to withdraw
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external virtual onlyOwner {
        token.safeTransfer(recipient, amount);
        emit WithdrawAssets(token, _msgSender(), recipient, amount);
    }

    /**
     * @notice Redeem all assets and close the order
     * @param recipient Recipient address for redeemed assets
     * @return badDebt Amount of bad debt if any
     */
    function redeemAll(address recipient)
        external
        virtual
        nonReentrant
        onlyOwner
        returns (uint256 badDebt, bytes memory deliveryData)
    {
        IERC4626 _pool = pool;
        uint256 ftBalance = ft.balanceOf(address(this));
        uint256 received;
        uint256 receivedFromPool;

        (received, deliveryData) = market.redeem(ftBalance, recipient);
        // if pool is set, redeem all shares
        if (address(_pool) != address(0)) {
            receivedFromPool = _pool.redeem(_pool.balanceOf(address(this)), recipient, address(this));
        }
        // Calculate bad debt
        badDebt = ftBalance - received;
        // Clear order configuration
        delete _orderConfig;
        emit OrderEventsV2.Redeemed(recipient, received + receivedFromPool, badDebt, deliveryData);
    }

    function withdrawAllAssetsBeforeMaturity(address recipient)
        external
        virtual
        nonReentrant
        onlyOwner
        returns (uint256 debtTokenAmount, uint256 ftAmount, uint256 xtAmount)
    {
        IERC4626 _pool = pool;
        IERC20 _ft = ft;
        IERC20 _xt = xt;
        if (_pool != IERC4626(address(0))) {
            uint256 shares = _pool.balanceOf(address(this));
            if (shares != 0) {
                debtTokenAmount += _pool.redeem(shares, recipient, address(this));
            }
        }
        ftAmount = _ft.balanceOf(address(this));
        xtAmount = _xt.balanceOf(address(this));
        uint256 maxBurned = ftAmount.min(xtAmount);
        if (maxBurned != 0) {
            market.burn(address(this), maxBurned);
            ftAmount -= maxBurned;
            xtAmount -= maxBurned;
        }
        if (ftAmount != 0) {
            _ft.safeTransfer(recipient, ftAmount);
        }
        if (xtAmount != 0) {
            _xt.safeTransfer(recipient, xtAmount);
        }

        emit OrderEventsV2.RedeemedAllBeforeMaturity(recipient, debtTokenAmount + maxBurned, ftAmount, xtAmount);
    }

    function borrowToken(address recipient, uint256 amount) external virtual nonReentrant onlyOwner {
        uint256 ftAmount = ft.balanceOf(address(this));
        uint256 xtAmount = xt.balanceOf(address(this));
        uint256 maxBurned = ftAmount.min(xtAmount);
        if (maxBurned < amount) {
            uint256 remainingAmount = amount - maxBurned;
            // issue ft from existing gt
            _issueFtToSelf(remainingAmount, _orderConfig.gtId);
        }
        market.burn(recipient, amount);
        emit OrderEventsV2.Borrowed(recipient, amount);
    }

    // =============================================================================
    // SWAP FUNCTIONS - PUBLIC INTERFACES
    // =============================================================================

    /**
     * @notice Swap exact amount of input token for output token
     * @inheritdoc ITermMaxOrder
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param recipient Recipient of output tokens
     * @param tokenAmtIn Exact input token amount
     * @param minTokenOut Minimum output token amount
     * @param deadline Transaction deadline
     * @return netTokenOut Actual output token amount
     */
    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtIn,
        uint128 minTokenOut,
        uint256 deadline
    ) external virtual override nonReentrant isOpen returns (uint256 netTokenOut) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        uint256 feeAmt;
        if (tokenAmtIn != 0) {
            IERC20 _debtToken = debtToken;
            IERC20 _ft = ft;
            IERC20 _xt = xt;
            OrderConfig memory orderConfig_ = _orderConfig;
            orderConfig_.feeConfig = market.config().feeConfig;
            int256 deltaFt;
            int256 deltaXt;
            if (tokenIn == _ft && tokenOut == _debtToken) {
                (netTokenOut, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtIn, minTokenOut, orderConfig_, _sellFt);
            } else if (tokenIn == _xt && tokenOut == _debtToken) {
                (netTokenOut, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtIn, minTokenOut, orderConfig_, _sellXt);
            } else if (tokenIn == _debtToken && tokenOut == _ft) {
                (netTokenOut, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtIn, minTokenOut, orderConfig_, _buyFt);
            } else if (tokenIn == _debtToken && tokenOut == _xt) {
                (netTokenOut, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtIn, minTokenOut, orderConfig_, _buyXt);
            } else {
                revert CantNotSwapToken(tokenIn, tokenOut);
            }

            uint256 ftBalance = ft.balanceOf(address(this));
            uint256 xtBalance = xt.balanceOf(address(this));
            if (orderConfig_.swapTrigger != ISwapCallback(address(0))) {
                orderConfig_.swapTrigger.afterSwap(ftBalance, xtBalance, deltaFt, deltaXt);
            }

            // transfer token in
            tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);

            _rebalance(
                _ft, _xt, _debtToken, tokenAmtIn, tokenOut, netTokenOut, feeAmt, orderConfig_.gtId, deltaFt, deltaXt
            );

            // transfer output tokens
            tokenOut.safeTransfer(recipient, netTokenOut);
        }

        emit SwapExactTokenToToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtIn, netTokenOut.toUint128(), feeAmt.toUint128()
        );
    }

    /**
     * @notice Swap input token for exact amount of output token
     * @inheritdoc ITermMaxOrder
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param recipient Recipient of output tokens
     * @param tokenAmtOut Exact output token amount
     * @param maxTokenIn Maximum input token amount
     * @param deadline Transaction deadline
     * @return netTokenIn Actual input token amount used
     */
    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtOut,
        uint128 maxTokenIn,
        uint256 deadline
    ) external virtual override nonReentrant isOpen returns (uint256 netTokenIn) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        uint256 feeAmt;
        if (tokenAmtOut != 0 && maxTokenIn != 0) {
            IERC20 _debtToken = debtToken;
            IERC20 _ft = ft;
            IERC20 _xt = xt;
            int256 deltaFt;
            int256 deltaXt;
            OrderConfig memory orderConfig_ = _orderConfig;
            orderConfig_.feeConfig = market.config().feeConfig;
            if (tokenIn == _debtToken && tokenOut == _ft) {
                (netTokenIn, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, orderConfig_, _buyExactFt);
            } else if (tokenIn == _debtToken && tokenOut == _xt) {
                (netTokenIn, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, orderConfig_, _buyExactXt);
            } else if (tokenIn == _ft && tokenOut == _debtToken) {
                (netTokenIn, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, orderConfig_, _sellFtForExactToken);
            } else if (tokenIn == _xt && tokenOut == _debtToken) {
                (netTokenIn, feeAmt, deltaFt, deltaXt) =
                    _swapAndUpdateReserves(tokenAmtOut, maxTokenIn, orderConfig_, _sellXtForExactToken);
            } else {
                revert CantNotSwapToken(tokenIn, tokenOut);
            }
            // trigger call back function
            if (orderConfig_.swapTrigger != ISwapCallback(address(0))) {
                orderConfig_.swapTrigger.afterSwap(
                    ft.balanceOf(address(this)), xt.balanceOf(address(this)), deltaFt, deltaXt
                );
            }

            // transfer token in
            tokenIn.safeTransferFrom(msg.sender, address(this), netTokenIn);
            _rebalance(
                _ft, _xt, _debtToken, netTokenIn, tokenOut, tokenAmtOut, feeAmt, orderConfig_.gtId, deltaFt, deltaXt
            );

            // transfer output tokens
            tokenOut.safeTransfer(recipient, tokenAmtOut);
        }

        emit SwapTokenToExactToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtOut, netTokenIn.toUint128(), feeAmt.toUint128()
        );
    }

    function _rebalance(
        IERC20 _ft,
        IERC20 _xt,
        IERC20 _debtToken,
        uint256 inputAmt,
        IERC20 tokenOut,
        uint256 outputAmt,
        uint256 feeAmt,
        uint256 gtId,
        int256 deltaFt,
        int256 deltaXt
    ) internal {
        // Rebalance the reserves after swap
        int256 newFtReserve = _ft.balanceOf(address(this)).toInt256() + deltaFt;
        int256 newXtReserve = _xt.balanceOf(address(this)).toInt256() + deltaXt;
        // check if need to release liquidity from pool or gt
        uint256 releaseAmount;
        if (newFtReserve < 0) {
            if (gtId != 0) {
                _issueFtToSelf(uint256(-newFtReserve), gtId);
            } else {
                releaseAmount = uint256(-newFtReserve);
            }
        } else if (newXtReserve < 0) {
            releaseAmount = uint256(-newXtReserve);
        }
        if (releaseAmount != 0) {
            IERC4626 pool_ = pool;
            if (pool_ == IERC4626(address(0))) {
                revert TermMaxCurve.InsufficientLiquidity();
            }
            pool_.withdraw(releaseAmount, address(this), address(this));
        }
        ITermMaxMarket _market = market;
        uint256 tokenToMint;
        if (tokenOut == _debtToken) {
            if (outputAmt > releaseAmount) {
                uint256 tokenToBurn = outputAmt - releaseAmount;
                _market.burn(address(this), tokenToBurn);
            } else {
                // If output token is debt token, we need to mint it
                tokenToMint = releaseAmount - outputAmt;
            }
        } else {
            tokenToMint = releaseAmount + inputAmt;
        }
        if (tokenToMint != 0) {
            _debtToken.safeIncreaseAllowance(address(_market), tokenToMint);
            _market.mint(address(this), tokenToMint);
        }

        // Pay fee
        _ft.safeTransfer(_market.config().treasurer, feeAmt);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS - CONFIGURATION UPDATES
    // =============================================================================

    /**
     * @notice Internal function to update curve cuts
     * @param newCurveCuts New curve cuts to validate and set
     */
    function _updateCurve(CurveCuts memory newCurveCuts) internal {
        if (newCurveCuts.lendCurveCuts.length > 0) {
            if (newCurveCuts.lendCurveCuts[0].liqSquare == 0 || newCurveCuts.lendCurveCuts[0].xtReserve != 0) {
                revert InvalidCurveCuts();
            }
        }
        for (uint256 i = 1; i < newCurveCuts.lendCurveCuts.length; i++) {
            if (
                newCurveCuts.lendCurveCuts[i].liqSquare == 0
                    || newCurveCuts.lendCurveCuts[i].xtReserve <= newCurveCuts.lendCurveCuts[i - 1].xtReserve
            ) {
                revert InvalidCurveCuts();
            }
            /*
                    R := (x' + beta') ^ 2 * DECIMAL_BASE / (x' + beta) ^ 2
                    L' ^ 2 := L ^ 2 * R / DECIMAL_BASE
                */
            if (
                newCurveCuts.lendCurveCuts[i].liqSquare
                    != (
                        newCurveCuts.lendCurveCuts[i - 1].liqSquare
                            * (
                                newCurveCuts.lendCurveCuts[i].xtReserve.plusInt256(newCurveCuts.lendCurveCuts[i].offset) ** 2
                                    * Constants.DECIMAL_BASE
                                    / newCurveCuts.lendCurveCuts[i].xtReserve.plusInt256(newCurveCuts.lendCurveCuts[i - 1].offset)
                                        ** 2
                            )
                    ) / Constants.DECIMAL_BASE
            ) revert InvalidCurveCuts();
        }
        if (newCurveCuts.borrowCurveCuts.length > 0) {
            if (newCurveCuts.borrowCurveCuts[0].liqSquare == 0 || newCurveCuts.borrowCurveCuts[0].xtReserve != 0) {
                revert InvalidCurveCuts();
            }
        }
        for (uint256 i = 1; i < newCurveCuts.borrowCurveCuts.length; i++) {
            if (
                newCurveCuts.borrowCurveCuts[i].liqSquare == 0
                    || newCurveCuts.borrowCurveCuts[i].xtReserve <= newCurveCuts.borrowCurveCuts[i - 1].xtReserve
            ) {
                revert InvalidCurveCuts();
            }
            if (
                newCurveCuts.borrowCurveCuts[i].liqSquare
                    != (
                        newCurveCuts.borrowCurveCuts[i - 1].liqSquare
                            * (
                                newCurveCuts.borrowCurveCuts[i].xtReserve.plusInt256(newCurveCuts.borrowCurveCuts[i].offset)
                                    ** 2 * Constants.DECIMAL_BASE
                                    / newCurveCuts.borrowCurveCuts[i].xtReserve.plusInt256(
                                        newCurveCuts.borrowCurveCuts[i - 1].offset
                                    ) ** 2
                            )
                    ) / Constants.DECIMAL_BASE
            ) revert InvalidCurveCuts();
        }
        _orderConfig.curveCuts = newCurveCuts;
    }

    // =============================================================================
    // INTERNAL FUNCTIONS - SWAP LOGIC
    // =============================================================================

    /**
     * @notice Internal function to execute swap and update reserves
     * @param tokenAmtInOrOut Token amount input or output
     * @param limitTokenAmt Limit for slippage protection
     * @param func Function pointer for specific swap calculation
     * @return netAmt Net amount after swap
     * @return feeAmt Fee amount charged
     */
    function _swapAndUpdateReserves(
        uint256 tokenAmtInOrOut,
        uint256 limitTokenAmt,
        OrderConfig memory orderConfig_,
        function(
        uint256,
        uint256,
        OrderConfig memory) internal view returns (uint256, uint256, uint256, uint256, bool) func
    ) private returns (uint256, uint256, int256, int256) {
        (uint256 netAmt, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(tokenAmtInOrOut, limitTokenAmt, orderConfig_);

        uint256 newXtReserve = virtualXtReserve;
        if (isNegetiveXt) {
            virtualXtReserve = newXtReserve - deltaXt;
            return (netAmt, feeAmt, deltaFt.toInt256(), -deltaXt.toInt256());
        } else {
            newXtReserve += deltaXt;
            // check xt reserve when lending to order
            if (newXtReserve > orderConfig_.maxXtReserve) {
                revert XtReserveTooHigh();
            }
            virtualXtReserve = newXtReserve;
            return (netAmt, feeAmt, -deltaFt.toInt256(), deltaXt.toInt256());
        }
    }

    /**
     * @notice Calculate mint amount needed for token operations
     * @param tokenToMint Total tokens needed to mint
     * @param netTokenOut Net output tokens
     * @param ftBalance Current FT balance
     * @param xtBalance Current XT balance
     * @return Calculated mint amount
     */
    function _calculateMintAmount(uint256 tokenToMint, uint256 netTokenOut, uint256 ftBalance, uint256 xtBalance)
        private
        pure
        returns (uint256)
    {
        uint256 mintAmount = tokenToMint - ftBalance;
        uint256 xtShortfall = netTokenOut > xtBalance ? netTokenOut - xtBalance : 0;
        return mintAmount > xtShortfall ? mintAmount : xtShortfall;
    }

    /**
     * @notice Issue FT tokens to self when needed
     * @param amount Amount of FT to issue
     * @param gtId The gearing token ID
     */
    function _issueFtToSelf(uint256 amount, uint256 gtId) internal {
        if (gtId == 0) revert CantNotIssueFtWithoutGt();
        uint256 debtAmtToIssue = (amount * Constants.DECIMAL_BASE) / (Constants.DECIMAL_BASE - market.mintGtFeeRatio());
        market.issueFtByExistedGt(address(this), (debtAmtToIssue).toUint128(), gtId);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS - TOKEN BUYING (LENDING)
    // =============================================================================

    /**
     * @notice Buy FT tokens with debt tokens (lending operation)
     * @param debtTokenAmtIn Debt token input amount
     * @param minTokenOut Minimum FT output
     * @param config Order configuration
     * @return netOut Net FT output
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyFt(uint256 debtTokenAmtIn, uint256 minTokenOut, OrderConfig memory config)
        internal
        view
        onlyLendingIsAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _buyToken(debtTokenAmtIn, minTokenOut, config, _buyFtStep);
    }

    /**
     * @notice Buy XT tokens with debt tokens (borrowing operation)
     * @param debtTokenAmtIn Debt token input amount
     * @param minTokenOut Minimum XT output
     * @param config Order configuration
     * @return netOut Net XT output
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyXt(uint256 debtTokenAmtIn, uint256 minTokenOut, OrderConfig memory config)
        internal
        view
        onlyBorrowingIsAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _buyToken(debtTokenAmtIn, minTokenOut, config, _buyXtStep);
    }

    /**
     * @notice Buy exact amount of FT tokens
     * @param tokenAmtOut Exact FT amount to buy
     * @param maxTokenIn Maximum debt token input
     * @param config Order configuration
     * @return netTokenIn Debt token input used
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyExactFt(uint256 tokenAmtOut, uint256 maxTokenIn, OrderConfig memory config)
        internal
        view
        onlyLendingIsAllowed(config)
        returns (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _buyExactToken(tokenAmtOut, maxTokenIn, config, _buyExactFtStep);
    }

    /**
     * @notice Buy exact amount of XT tokens
     * @param tokenAmtOut Exact XT amount to buy
     * @param maxTokenIn Maximum debt token input
     * @param config Order configuration
     * @return netTokenIn Debt token input used
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyExactXt(uint256 tokenAmtOut, uint256 maxTokenIn, OrderConfig memory config)
        internal
        view
        onlyBorrowingIsAllowed(config)
        returns (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _buyExactToken(tokenAmtOut, maxTokenIn, config, _buyExactXtStep);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS - TOKEN SELLING
    // =============================================================================

    /**
     * @notice Sell FT tokens for debt tokens (borrowing operation)
     * @param ftAmtIn FT input amount
     * @param minDebtTokenOut Minimum debt token output
     * @param config Order configuration
     * @return netOut Net debt token output
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellFt(uint256 ftAmtIn, uint256 minDebtTokenOut, OrderConfig memory config)
        internal
        view
        onlyBorrowingIsAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _sellToken(ftAmtIn, minDebtTokenOut, config, _sellFtStep);
    }

    /**
     * @notice Sell XT tokens for debt tokens (lending operation)
     * @param xtAmtIn XT input amount
     * @param minDebtTokenOut Minimum debt token output
     * @param config Order configuration
     * @return netOut Net debt token output
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellXt(uint256 xtAmtIn, uint256 minDebtTokenOut, OrderConfig memory config)
        internal
        view
        onlyLendingIsAllowed(config)
        returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) = _sellToken(xtAmtIn, minDebtTokenOut, config, _sellXtStep);
    }

    /**
     * @notice Sell FT for exact amount of debt tokens
     * @param debtTokenAmtOut Exact debt token output
     * @param maxFtIn Maximum FT input
     * @param config Order configuration
     * @return netIn FT input used
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellFtForExactToken(uint256 debtTokenAmtOut, uint256 maxFtIn, OrderConfig memory config)
        internal
        view
        onlyBorrowingIsAllowed(config)
        returns (uint256 netIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _sellTokenForExactToken(debtTokenAmtOut, maxFtIn, config, _sellFtForExactTokenStep);
    }

    /**
     * @notice Sell XT for exact amount of debt tokens
     * @param debtTokenAmtOut Exact debt token output
     * @param maxXtIn Maximum XT input
     * @param config Order configuration
     * @return netIn XT input used
     * @return feeAmt Fee amount
     * @return deltaFt Change in FT reserve
     * @return deltaXt Change in XT reserve
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellXtForExactToken(uint256 debtTokenAmtOut, uint256 maxXtIn, OrderConfig memory config)
        internal
        view
        onlyLendingIsAllowed(config)
        returns (uint256 netIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        (netIn, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            _sellTokenForExactToken(debtTokenAmtOut, maxXtIn, config, _sellXtForExactTokenStep);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS - SWAP CALCULATION HELPERS
    // =============================================================================

    /**
     * @notice Generic token buying logic
     * @param debtTokenAmtIn Debt token input
     * @param minTokenOut Minimum token output
     * @param config Order configuration
     * @param func Specific step function
     * @return netOut Net output
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyToken(
        uint256 debtTokenAmtIn,
        uint256 minTokenOut,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal pure returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) {
        (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt) =
            func(_daysToMaturity(), virtualXtReserve, debtTokenAmtIn, config);

        netOut += debtTokenAmtIn;
        if (netOut < minTokenOut) revert UnexpectedAmount(minTokenOut, netOut);
        return (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    /**
     * @notice Generic exact token buying logic
     * @param tokenAmtOut Exact token output
     * @param maxTokenIn Maximum token input
     * @param config Order configuration
     * @param func Specific step function
     * @return netTokenIn Token input used
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyExactToken(
        uint256 tokenAmtOut,
        uint256 maxTokenIn,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal pure returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256, uint256, uint256, uint256, bool) {
        (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(_daysToMaturity(), virtualXtReserve, tokenAmtOut, config);

        if (netTokenIn > maxTokenIn) revert UnexpectedAmount(maxTokenIn, netTokenIn);

        return (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    /**
     * @notice Generic token selling logic
     * @param tokenAmtIn Token input
     * @param minDebtTokenOut Minimum debt token output
     * @param config Order configuration
     * @param func Specific step function
     * @return netOut Net output
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellToken(
        uint256 tokenAmtIn,
        uint256 minDebtTokenOut,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal pure returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256, uint256, uint256, uint256, bool) {
        (uint256 netOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(_daysToMaturity(), virtualXtReserve, tokenAmtIn, config);
        if (netOut < minDebtTokenOut) revert UnexpectedAmount(minDebtTokenOut, netOut);
        return (netOut, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    /**
     * @notice Generic exact token selling logic
     * @param debtTokenAmtOut Exact debt token output
     * @param maxTokenIn Maximum token input
     * @param config Order configuration
     * @param func Specific step function
     * @return netTokenIn Token input used
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellTokenForExactToken(
        uint256 debtTokenAmtOut,
        uint256 maxTokenIn,
        OrderConfig memory config,
        function(uint256, uint256, uint256, OrderConfig memory) internal pure returns (uint256, uint256, uint256, uint256, bool)
            func
    ) internal view returns (uint256, uint256, uint256, uint256, bool) {
        (uint256 netTokenIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) =
            func(_daysToMaturity(), virtualXtReserve, debtTokenAmtOut, config);

        if (netTokenIn > maxTokenIn) revert UnexpectedAmount(maxTokenIn, netTokenIn);

        return (netTokenIn, feeAmt, deltaFt, deltaXt, isNegetiveXt);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS - CURVE CALCULATION STEPS
    // =============================================================================

    /**
     * @notice Calculate FT buying step using curve mathematics
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param debtTokenAmtIn Debt token input
     * @param config Order configuration
     * @return tokenAmtOut FT tokens output
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyFtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 debtTokenAmtIn, OrderConfig memory config)
        internal
        pure
        returns (uint256 tokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, tokenAmtOut) = TermMaxCurve.buyFt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = (tokenAmtOut * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif - tokenAmtOut;

        // ft reserve decrease, xt reserve increase
        deltaFt = tokenAmtOut + feeAmt;
        isNegetiveXt = false;
    }

    /**
     * @notice Calculate XT buying step using curve mathematics
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param debtTokenAmtIn Debt token input
     * @param config Order configuration
     * @return tokenAmtOut XT tokens output
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyXtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 debtTokenAmtIn, OrderConfig memory config)
        internal
        pure
        returns (uint256 tokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);
        (tokenAmtOut, deltaFt) = TermMaxCurve.buyXt(nif, daysToMaturity, cuts, oriXtReserve, debtTokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        deltaXt = tokenAmtOut;
        isNegetiveXt = true;
    }

    /**
     * @notice Calculate exact FT buying step
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param ftAmtOut Exact FT output
     * @param config Order configuration
     * @return debtTokenAmtIn Debt token input needed
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyExactFtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 ftAmtOut, OrderConfig memory config)
        internal
        pure
        returns (uint256 debtTokenAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, deltaFt) = TermMaxCurve.buyExactFt(nif, daysToMaturity, cuts, oriXtReserve, ftAmtOut);
        debtTokenAmtIn = deltaXt;
        feeAmt = (deltaFt * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif - deltaFt;

        // ft reserve decrease, xt reserve increase
        deltaFt += feeAmt;
        isNegetiveXt = false;
    }

    /**
     * @notice Calculate exact XT buying step
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param xtAmtOut Exact XT output
     * @param config Order configuration
     * @return debtTokenAmtIn Debt token input needed
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _buyExactXtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 xtAmtOut, OrderConfig memory config)
        internal
        pure
        returns (uint256 debtTokenAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);
        (deltaXt, deltaFt) = TermMaxCurve.buyExactXt(nif, daysToMaturity, cuts, oriXtReserve, xtAmtOut);
        debtTokenAmtIn = deltaFt;
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        isNegetiveXt = true;
    }

    /**
     * @notice Calculate FT selling step
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param tokenAmtIn FT input
     * @param config Order configuration
     * @return debtTokenAmtOut Debt token output
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellFtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 tokenAmtIn, OrderConfig memory config)
        internal
        pure
        returns (uint256 debtTokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);
        (debtTokenAmtOut, deltaFt) = TermMaxCurve.sellFt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        deltaXt = debtTokenAmtOut;
        isNegetiveXt = true;
    }

    /**
     * @notice Calculate XT selling step
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param tokenAmtIn XT input
     * @param config Order configuration
     * @return debtTokenAmtOut Debt token output
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellXtStep(uint256 daysToMaturity, uint256 oriXtReserve, uint256 tokenAmtIn, OrderConfig memory config)
        internal
        pure
        returns (uint256 debtTokenAmtOut, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt)
    {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, debtTokenAmtOut) = TermMaxCurve.sellXt(nif, daysToMaturity, cuts, oriXtReserve, tokenAmtIn);
        feeAmt = (debtTokenAmtOut * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif
            - debtTokenAmtOut;

        // ft reserve decrease, xt reserve increase
        deltaFt = debtTokenAmtOut + feeAmt;
        isNegetiveXt = false;
    }

    /**
     * @notice Calculate FT selling for exact debt token step
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param debtTokenOut Exact debt token output
     * @param config Order configuration
     * @return ftAmtIn FT input needed
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellFtForExactTokenStep(
        uint256 daysToMaturity,
        uint256 oriXtReserve,
        uint256 debtTokenOut,
        OrderConfig memory config
    ) internal pure returns (uint256 ftAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.lendCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE + uint256(feeConfig.borrowTakerFeeRatio);

        (deltaXt, deltaFt) = TermMaxCurve.sellFtForExactDebtToken(nif, daysToMaturity, cuts, oriXtReserve, debtTokenOut);
        ftAmtIn = deltaFt + debtTokenOut;

        feeAmt = deltaFt - (deltaFt * (Constants.DECIMAL_BASE - uint256(feeConfig.lendMakerFeeRatio))) / nif;

        // ft reserve increase, xt reserve decrease
        deltaFt -= feeAmt;
        isNegetiveXt = true;
    }

    /**
     * @notice Calculate XT selling for exact debt token step
     * @param daysToMaturity Days until maturity
     * @param oriXtReserve Original XT reserve
     * @param debtTokenOut Exact debt token output
     * @param config Order configuration
     * @return xtAmtIn XT input needed
     * @return feeAmt Fee amount
     * @return deltaFt FT reserve change
     * @return deltaXt XT reserve change
     * @return isNegetiveXt Whether XT change is negative
     */
    function _sellXtForExactTokenStep(
        uint256 daysToMaturity,
        uint256 oriXtReserve,
        uint256 debtTokenOut,
        OrderConfig memory config
    ) internal pure returns (uint256 xtAmtIn, uint256 feeAmt, uint256 deltaFt, uint256 deltaXt, bool isNegetiveXt) {
        FeeConfig memory feeConfig = config.feeConfig;
        CurveCut[] memory cuts = config.curveCuts.borrowCurveCuts;
        uint256 nif = Constants.DECIMAL_BASE - uint256(feeConfig.lendTakerFeeRatio);
        (deltaXt, deltaFt) = TermMaxCurve.sellXtForExactDebtToken(nif, daysToMaturity, cuts, oriXtReserve, debtTokenOut);
        xtAmtIn = deltaXt + debtTokenOut;

        feeAmt = (deltaFt * (Constants.DECIMAL_BASE + uint256(feeConfig.borrowMakerFeeRatio))) / nif - deltaFt;

        // ft reserve decrease, xt reserve increase
        deltaFt += feeAmt;
        isNegetiveXt = false;
    }
}
