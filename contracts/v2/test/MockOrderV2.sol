// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxOrder, IERC20} from "../../v1/ITermMaxOrder.sol";
import {ITermMaxMarket} from "../../v1/ITermMaxMarket.sol";
import {IGearingToken} from "../../v1/tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "../../v1/IFlashLoanReceiver.sol";
import {Constants} from "../../v1/lib/Constants.sol";
import {TermMaxCurve, MathLib} from "../../v1/lib/TermMaxCurve.sol";
import {OrderErrors} from "../../v1/errors/OrderErrors.sol";
import {OrderEvents} from "../../v1/events/OrderEvents.sol";
import {OrderConfig, MarketConfig, CurveCuts, CurveCut, FeeConfig} from "../../v1/storage/TermMaxStorage.sol";
import {ISwapCallback} from "../../v1/ISwapCallback.sol";
import {TransferUtils} from "../../v1/lib/TransferUtils.sol";
import {ITermMaxMarketV2} from "../ITermMaxMarketV2.sol";
import {OrderEventsV2} from "../events/OrderEventsV2.sol";
import {ITermMaxOrderV2, OrderInitialParams, IERC4626} from "../ITermMaxOrderV2.sol";

/**
 * @title TermMax Order
 * @author Term Structure Labs
 */
contract MockOrderV2 is
    ITermMaxOrder,
    ITermMaxOrderV2,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    OrderErrors,
    OrderEvents
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for uint128;
    using TransferUtils for IERC20;
    using TransferUtils for IERC4626;

    ITermMaxMarket public market;

    IERC20 private ft;
    IERC20 private xt;
    IERC20 private debtToken;
    IGearingToken private gt;

    OrderConfig private _orderConfig;

    address public maker;

    uint64 private maturity;

    /// @notice Check if the market is borrowing allowed
    modifier isBorrowingAllowed(OrderConfig memory config) {
        if (config.curveCuts.borrowCurveCuts.length == 0) {
            revert BorrowIsNotAllowed();
        }
        _;
    }

    /// @notice Check if the market is lending allowed
    modifier isLendingAllowed(OrderConfig memory config) {
        if (config.curveCuts.lendCurveCuts.length == 0) {
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

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function initialize(
        address maker_,
        IERC20[3] memory tokens,
        IGearingToken gt_,
        uint256 maxXtReserve_,
        ISwapCallback swapTrigger,
        CurveCuts memory curveCuts_,
        MarketConfig memory marketConfig
    ) external override initializer {
        __Ownable_init(maker_);
        __ReentrancyGuard_init();
        __Pausable_init();
        market = ITermMaxMarket(_msgSender());
        maker = maker_;
        _orderConfig.curveCuts = curveCuts_;
        _orderConfig.feeConfig = marketConfig.feeConfig;
        _orderConfig.maxXtReserve = maxXtReserve_;
        _orderConfig.swapTrigger = swapTrigger;
        maturity = marketConfig.maturity;

        ft = tokens[0];
        xt = tokens[1];
        debtToken = tokens[2];
        gt = gt_;
        emit OrderInitialized(market, maker_, maxXtReserve_, swapTrigger, curveCuts_);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function orderConfig() external view returns (OrderConfig memory) {
        return _orderConfig;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function tokenReserves() public view override returns (uint256, uint256) {
        return (ft.balanceOf(address(this)), xt.balanceOf(address(this)));
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function apr() external view override returns (uint256 lendApr_, uint256 borrowApr_) {
        uint256 daysToMaturity = _daysToMaturity();
        uint256 oriXtReserve = xt.balanceOf(address(this));

        CurveCuts memory curveCuts = _orderConfig.curveCuts;

        uint256 lendCutId = TermMaxCurve.calcCutId(curveCuts.lendCurveCuts, oriXtReserve);
        (, uint256 lendVXtReserve, uint256 lendVFtReserve) = TermMaxCurve.calcIntervalProps(
            Constants.DECIMAL_BASE, daysToMaturity, curveCuts.lendCurveCuts[lendCutId], oriXtReserve
        );
        lendApr_ =
            ((lendVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / lendVXtReserve) * daysToMaturity;

        uint256 borrowCutId = TermMaxCurve.calcCutId(curveCuts.borrowCurveCuts, oriXtReserve);
        (, uint256 borrowVXtReserve, uint256 borrowVFtReserve) = TermMaxCurve.calcIntervalProps(
            Constants.DECIMAL_BASE, daysToMaturity, curveCuts.borrowCurveCuts[borrowCutId], oriXtReserve
        );
        borrowApr_ =
            ((borrowVFtReserve * Constants.DECIMAL_BASE * Constants.DAYS_IN_YEAR) / borrowVXtReserve) * daysToMaturity;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function updateOrder(OrderConfig memory newOrderConfig, int256 ftChangeAmt, int256 xtChangeAmt)
        external
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

    function _updateCurve(CurveCuts memory newCurveCuts) internal {
        bytes32 newCurveCutsHash = keccak256(abi.encode(newCurveCuts));
        CurveCuts memory oldCurveCuts = _orderConfig.curveCuts;
        if (keccak256(abi.encode(oldCurveCuts)) != newCurveCutsHash) {
            if (newCurveCuts.lendCurveCuts.length > 0) {
                if (newCurveCuts.lendCurveCuts[0].xtReserve != 0) revert InvalidCurveCuts();
            }
            for (uint256 i = 1; i < newCurveCuts.lendCurveCuts.length; i++) {
                if (newCurveCuts.lendCurveCuts[i].xtReserve <= newCurveCuts.lendCurveCuts[i - 1].xtReserve) {
                    revert InvalidCurveCuts();
                }
            }
            if (newCurveCuts.borrowCurveCuts.length > 0) {
                if (newCurveCuts.borrowCurveCuts[0].xtReserve != 0) revert InvalidCurveCuts();
            }
            for (uint256 i = 1; i < newCurveCuts.borrowCurveCuts.length; i++) {
                if (newCurveCuts.borrowCurveCuts[i].xtReserve <= newCurveCuts.borrowCurveCuts[i - 1].xtReserve) {
                    revert InvalidCurveCuts();
                }
            }
            _orderConfig.curveCuts = newCurveCuts;
        }
    }

    function updateFeeConfig(FeeConfig memory newFeeConfig) external override onlyMarket {
        _orderConfig.feeConfig = newFeeConfig;
        emit UpdateFeeConfig(newFeeConfig);
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity() internal view returns (uint256 daysToMaturity) {
        daysToMaturity = (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) / Constants.SECONDS_IN_DAY;
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function swapExactTokenToToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtIn,
        uint128 minTokenOut,
        uint256
    ) external override nonReentrant isOpen returns (uint256 netTokenOut) {
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        uint256 feeAmt = 0;

        int256 deltaFt;
        int256 deltaXt;
        if (tokenIn == debtToken && tokenOut == ft) {
            deltaFt = -(minTokenOut - tokenAmtIn).toInt256();
            deltaXt = tokenAmtIn.toInt256();
        } else if (tokenIn == debtToken && tokenOut == xt) {
            deltaFt = tokenAmtIn.toInt256();
            deltaXt = -(minTokenOut - tokenAmtIn).toInt256();
        } else if (tokenIn == ft && tokenOut == debtToken) {
            deltaFt = (tokenAmtIn - minTokenOut).toInt256();
            deltaXt = -minTokenOut.toInt256();
        } else if (tokenIn == xt && tokenOut == debtToken) {
            deltaFt = -minTokenOut.toInt256();
            deltaXt = (tokenAmtIn - minTokenOut).toInt256();
        }

        if (address(_orderConfig.swapTrigger) != address(0)) {
            uint256 ftReserve = ft.balanceOf(address(this));
            uint256 xtReserve = xt.balanceOf(address(this));
            _orderConfig.swapTrigger.afterSwap(ftReserve, xtReserve, deltaFt, deltaXt);
        }

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);
        if (tokenIn == debtToken) {
            tokenIn.safeIncreaseAllowance(address(market), tokenAmtIn);
            market.mint(address(this), tokenAmtIn);
        }
        if (tokenOut == debtToken) {
            ITermMaxMarketV2(address(market)).burn(address(this), address(this), minTokenOut);
        }
        tokenOut.safeTransfer(recipient, minTokenOut);

        netTokenOut = minTokenOut;
        emit SwapExactTokenToToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtIn, netTokenOut.toUint128(), feeAmt.toUint128()
        );
    }

    function swapTokenToExactToken(
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint128 tokenAmtOut,
        uint128 maxTokenIn,
        uint256
    ) external nonReentrant isOpen returns (uint256 netTokenIn) {
        if (tokenIn == tokenOut) revert CantSwapSameToken();
        uint256 feeAmt = 0;

        int256 deltaFt;
        int256 deltaXt;
        if (tokenIn == debtToken && tokenOut == ft) {
            deltaFt = -(tokenAmtOut - maxTokenIn).toInt256();
            deltaXt = maxTokenIn.toInt256();
        } else if (tokenIn == debtToken && tokenOut == xt) {
            deltaFt = maxTokenIn.toInt256();
            deltaXt = -(tokenAmtOut - maxTokenIn).toInt256();
        } else if (tokenIn == ft && tokenOut == debtToken) {
            deltaFt = (maxTokenIn - tokenAmtOut).toInt256();
            deltaXt = -tokenAmtOut.toInt256();
        } else if (tokenIn == xt && tokenOut == debtToken) {
            deltaFt = -tokenAmtOut.toInt256();
            deltaXt = (maxTokenIn - tokenAmtOut).toInt256();
        }

        if (address(_orderConfig.swapTrigger) != address(0)) {
            uint256 ftReserve = ft.balanceOf(address(this));
            uint256 xtReserve = xt.balanceOf(address(this));
            _orderConfig.swapTrigger.afterSwap(ftReserve, xtReserve, deltaFt, deltaXt);
        }

        tokenIn.safeTransferFrom(msg.sender, address(this), maxTokenIn);
        if (tokenIn == debtToken) {
            tokenIn.safeIncreaseAllowance(address(market), maxTokenIn);
            market.mint(address(this), maxTokenIn);
        }
        if (tokenOut == debtToken) {
            ITermMaxMarketV2(address(market)).burn(address(this), address(this), tokenAmtOut);
        }
        tokenOut.safeTransfer(recipient, tokenAmtOut);
        netTokenIn = maxTokenIn;

        emit SwapTokenToExactToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtOut, netTokenIn.toUint128(), feeAmt.toUint128()
        );
    }

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        if (token == debtToken) {
            ITermMaxMarketV2(address(market)).burn(address(this), recipient, amount);
        } else {
            token.safeTransfer(recipient, amount);
        }
        emit WithdrawAssets(token, _msgSender(), recipient, amount);
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc ITermMaxOrder
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    function initialize(OrderInitialParams memory params) external override initializer {
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
        _orderConfig = params.orderConfig;

        // _updateGeneralConfig(
        //     params.orderConfig.gtId,
        //     params.orderConfig.maxXtReserve,
        //     params.orderConfig.swapTrigger,
        //     params.virtualXtReserve
        // );
        emit OrderEventsV2.OrderInitialized(params.maker, _market);
    }

    function getRealReserves() external view override returns (uint256 ftReserve, uint256 xtReserve) {}

    function setCurve(CurveCuts memory newCurveCuts) external override {}

    function setGeneralConfig(uint256 gtId, uint256 maxXtReserve, ISwapCallback swapTrigger, uint256 virtualXtReserve)
        external
        override
    {}

    function setPool(IERC4626 newPool) external override {}

    function addLiquidity(IERC20 asset, uint256 amount) external override {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.safeIncreaseAllowance(address(market), amount);
        market.mint(address(this), amount);
    }

    function removeLiquidity(IERC20, uint256 amount, address recipient) external override {
        market.burn(recipient, amount);
    }

    function redeemAll(IERC20 asset, address recipient)
        external
        override
        returns (uint256 badDebt, bytes memory deliveryData)
    {
        IERC4626 _pool = pool();
        IERC20 _debtToken = debtToken;
        uint256 ftBalance = ft.balanceOf(address(this));
        uint256 received;
        if (asset == _debtToken) {
            (received, deliveryData) = market.redeem(ftBalance, recipient);
            // if pool is set, redeem all shares
            if (address(_pool) != address(0)) {
                uint256 receivedFromPool = _pool.redeem(_pool.balanceOf(address(this)), recipient, address(this));
                emit OrderEventsV2.LiquidityRemoved(asset, receivedFromPool);
            } else {
                emit OrderEventsV2.LiquidityRemoved(asset, received);
            }
        } else {
            /// @dev You have to deal with the delivery data by yourself if you want to redeem to shares
            (received, deliveryData) = market.redeem(ftBalance, address(this));
            // if pool is set, withdraw all shares
            _debtToken.safeIncreaseAllowance(address(_pool), received);
            _pool.deposit(received, address(this));
            uint256 totalShares = _pool.balanceOf(address(this));
            _pool.safeTransfer(recipient, totalShares);
            emit OrderEventsV2.LiquidityRemoved(asset, totalShares);
        }
        // Calculate bad debt
        badDebt = ftBalance - received;
        // Clear order configuration
        delete _orderConfig;
    }

    function pool() public view override returns (IERC4626) {}

    function virtualXtReserve() external view override returns (uint256) {}
}
