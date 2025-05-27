// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITermMaxOrder, IERC20} from "../ITermMaxOrder.sol";
import {ITermMaxMarket} from "../ITermMaxMarket.sol";
import {IGearingToken} from "../tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "../IFlashLoanReceiver.sol";
import {Constants} from "../lib/Constants.sol";
import {TermMaxCurve, MathLib} from "../lib/TermMaxCurve.sol";
import {OrderErrors} from "../errors/OrderErrors.sol";
import {OrderEvents} from "../events/OrderEvents.sol";
import {OrderConfig, MarketConfig, CurveCuts, CurveCut, FeeConfig} from "../storage/TermMaxStorage.sol";
import {ISwapCallback} from "../ISwapCallback.sol";
import {TransferUtils} from "../lib/TransferUtils.sol";

/**
 * @title TermMax Order
 * @author Term Structure Labs
 */
contract MockOrder is
    ITermMaxOrder,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    OrderErrors,
    OrderEvents
{
    using SafeCast for uint256;
    using SafeCast for int256;
    using TransferUtils for IERC20;

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
        // check gtId
        if (newOrderConfig.gtId != 0 && address(this) != gt.getApproved(newOrderConfig.gtId)) {
            revert GtNotApproved(newOrderConfig.gtId);
        }
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
        uint256 ftBlanceBefore = ft.balanceOf(address(this));
        uint256 xtBlanceBefore = xt.balanceOf(address(this));

        tokenIn.safeTransferFrom(msg.sender, address(this), tokenAmtIn);
        if (tokenIn == debtToken) {
            tokenIn.safeIncreaseAllowance(address(market), tokenAmtIn);
            market.mint(address(this), tokenAmtIn);
        }
        if (tokenOut == debtToken) {
            ft.safeIncreaseAllowance(address(market), minTokenOut);
            xt.safeIncreaseAllowance(address(market), minTokenOut);
            market.burn(recipient, minTokenOut);
        } else {
            tokenOut.safeTransfer(recipient, minTokenOut);
        }

        netTokenOut = minTokenOut;

        if (address(_orderConfig.swapTrigger) != address(0)) {
            uint256 ftReserve = ft.balanceOf(address(this));
            uint256 xtReserve = xt.balanceOf(address(this));
            int256 deltaFt = ftReserve.toInt256() - ftBlanceBefore.toInt256();
            int256 deltaXt = xtReserve.toInt256() - xtBlanceBefore.toInt256();
            _orderConfig.swapTrigger.afterSwap(ftReserve, xtReserve, deltaFt, deltaXt);
        }
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
        uint256 ftBlanceBefore = ft.balanceOf(address(this));
        uint256 xtBlanceBefore = xt.balanceOf(address(this));

        tokenIn.safeTransferFrom(msg.sender, address(this), maxTokenIn);
        if (tokenIn == debtToken) {
            tokenIn.safeIncreaseAllowance(address(market), maxTokenIn);
            market.mint(address(this), maxTokenIn);
        }
        if (tokenOut == debtToken) {
            ft.safeIncreaseAllowance(address(market), tokenAmtOut);
            xt.safeIncreaseAllowance(address(market), tokenAmtOut);
            market.burn(recipient, tokenAmtOut);
        } else {
            tokenOut.safeTransfer(recipient, tokenAmtOut);
        }
        netTokenIn = maxTokenIn;

        if (address(_orderConfig.swapTrigger) != address(0)) {
            uint256 ftReserve = ft.balanceOf(address(this));
            uint256 xtReserve = xt.balanceOf(address(this));
            int256 deltaFt = ftReserve.toInt256() - ftBlanceBefore.toInt256();
            int256 deltaXt = xtReserve.toInt256() - xtBlanceBefore.toInt256();
            _orderConfig.swapTrigger.afterSwap(ftReserve, xtReserve, deltaFt, deltaXt);
        }
        emit SwapTokenToExactToken(
            tokenIn, tokenOut, msg.sender, recipient, tokenAmtOut, netTokenIn.toUint128(), feeAmt.toUint128()
        );
    }

    function withdrawAssets(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        token.safeTransfer(recipient, amount);
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
}
