// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {IMintableERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {TermMaxCurve, MathLib} from "./lib/TermMaxCurve.sol";
import {Constants} from "./lib/Constants.sol";
import {Ownable} from "./access/Ownable.sol";
import "./storage/TermMaxStorage.sol";

/**
 * @title Term Max Market
 * @author Term Structure Labs
 */
contract TermMaxMarket is ITermMaxMarket, ReentrancyGuard, Ownable, Pausable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using MathLib for *;

    MarketConfig _config;
    address collateral;
    IERC20 underlying;
    IMintableERC20 ft;
    IMintableERC20 xt;
    IMintableERC20 lpFt;
    IMintableERC20 lpXt;
    IGearingToken gt;

    /// @notice Check if the market is tradable
    modifier isOpen() {
        // Check pausable switch
        _requireNotPaused();
        if (block.timestamp < _config.openTime) {
            revert MarketIsNotOpen();
        }
        if (block.timestamp >= _config.maturity) {
            revert MarketWasClosed();
        }
        _;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function initialize(
        address admin,
        address collateral_,
        IERC20 underlying_,
        IMintableERC20[4] memory tokens_,
        IGearingToken gt_,
        MarketConfig memory config_
    ) external override {
        __initilizeOwner(admin);
        if (address(collateral_) == address(underlying_)) {
            revert CollateralCanNotEqualUnserlyinng();
        }
        if (
            config_.openTime < block.timestamp ||
            config_.maturity < config_.openTime
        ) {
            revert InvalidTime(config_.openTime, config_.maturity);
        }
        underlying = underlying_;
        collateral = collateral_;
        config_.rewardIsDistributed = false;
        _config = config_;

        ft = tokens_[0];
        xt = tokens_[1];
        lpFt = tokens_[2];
        lpXt = tokens_[3];
        gt = gt_;

        emit MarketInitialized(
            collateral,
            underlying,
            _config.openTime,
            _config.maturity,
            tokens_,
            gt_
        );
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
        override
        returns (
            IMintableERC20,
            IMintableERC20,
            IMintableERC20,
            IMintableERC20,
            IGearingToken,
            address,
            IERC20
        )
    {
        return (ft, xt, lpFt, lpXt, gt, collateral, underlying);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function setFeeRate(
        uint32 lendFeeRatio,
        uint32 minNLendFeeR,
        uint32 borrowFeeRatio,
        uint32 minNBorrowFeeR,
        uint32 redeemFeeRatio,
        uint32 issueFtFeeRatio,
        uint32 lockingPercentage,
        uint32 protocolFeeRatio
    ) external override onlyOwner {
        MarketConfig memory mConfig = _config;
        mConfig.lendFeeRatio = lendFeeRatio;
        mConfig.minNLendFeeR = minNLendFeeR;
        mConfig.borrowFeeRatio = borrowFeeRatio;
        mConfig.minNBorrowFeeR = minNBorrowFeeR;
        mConfig.redeemFeeRatio = redeemFeeRatio;
        mConfig.issueFtFeeRatio = issueFtFeeRatio;
        mConfig.lockingPercentage = lockingPercentage;
        mConfig.protocolFeeRatio = protocolFeeRatio;
        _config = mConfig;
        emit UpdateFeeRate(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            issueFtFeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function setTreasurer(address treasurer) external onlyOwner {
        _config.treasurer = treasurer;
        gt.setTreasurer(treasurer);

        emit UpdateTreasurer(treasurer);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function provideLiquidity(
        uint256 underlyingAmt
    )
        external
        isOpen
        nonReentrant
        returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt)
    {
        (lpFtOutAmt, lpXtOutAmt) = _provideLiquidity(msg.sender, underlyingAmt);
    }

    function _provideLiquidity(
        address caller,
        uint256 underlyingAmt
    ) internal returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt) {
        uint ftReserve = ft.balanceOf(address(this));
        uint lpFtTotalSupply = lpFt.totalSupply();

        uint xtReserve = xt.balanceOf(address(this));
        uint lpXtTotalSupply = lpXt.totalSupply();
        (uint128 ftMintedAmt, uint128 xtMintedAmt) = _addLiquidity(
            caller,
            underlyingAmt,
            _config.initialLtv
        );

        lpFtOutAmt = TermMaxCurve
            .calculateLpOut(ftMintedAmt, ftReserve, lpFtTotalSupply)
            .toUint128();

        lpXtOutAmt = TermMaxCurve
            .calculateLpOut(xtMintedAmt, xtReserve, lpXtTotalSupply)
            .toUint128();
        lpXt.mint(caller, lpXtOutAmt);
        lpFt.mint(caller, lpFtOutAmt);

        emit ProvideLiquidity(caller, underlyingAmt, lpFtOutAmt, lpXtOutAmt);
    }

    function _addLiquidity(
        address caller,
        uint256 underlyingAmt,
        uint256 ltv
    ) internal returns (uint128 ftMintedAmt, uint128 xtMintedAmt) {
        underlying.transferFrom(caller, address(this), underlyingAmt);

        ftMintedAmt = ((underlyingAmt * ltv) / Constants.DECIMAL_BASE)
            .toUint128();
        xtMintedAmt = underlyingAmt.toUint128();
        // Mint tokens to this
        ft.mint(address(this), ftMintedAmt);
        xt.mint(address(this), xtMintedAmt);
    }

    /// @notice Calculate how many days until expiration
    function _daysToMaturity(
        uint maturity
    ) internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) /
            Constants.SECONDS_IN_DAY;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function withdrawLp(
        uint128 lpFtAmt,
        uint128 lpXtAmt
    )
        external
        override
        isOpen
        nonReentrant
        returns (uint128 ftOutAmt, uint128 xtOutAmt)
    {
        (ftOutAmt, xtOutAmt) = _withdrawLp(msg.sender, lpFtAmt, lpXtAmt);
    }

    function _withdrawLp(
        address caller,
        uint256 lpFtAmt,
        uint256 lpXtAmt
    ) internal returns (uint128 ftOutAmt, uint128 xtOutAmt) {
        uint lpFtTotalSupply = lpFt.totalSupply();
        uint lpXtTotalSupply = lpXt.totalSupply();
        MarketConfig memory mConfig = _config;
        // calculate reward
        uint ftReserve = ft.balanceOf(address(this));
        if (lpFtAmt > 0) {
            uint reward = TermMaxCurve.calculateLpReward(
                block.timestamp,
                mConfig.openTime,
                mConfig.maturity,
                lpFtTotalSupply,
                lpFtAmt,
                lpFt.balanceOf(address(this))
            );

            lpFt.transferFrom(caller, address(this), lpFtAmt);

            lpFtAmt += reward;
            lpFt.burn(lpFtAmt);

            ftOutAmt = ((lpFtAmt * ftReserve) / lpFtTotalSupply).toUint128();
        }
        uint xtReserve = xt.balanceOf(address(this));
        if (lpXtAmt > 0) {
            uint reward = TermMaxCurve.calculateLpReward(
                block.timestamp,
                mConfig.openTime,
                mConfig.maturity,
                lpXtTotalSupply,
                lpXtAmt,
                lpXt.balanceOf(address(this))
            );
            lpXt.transferFrom(caller, address(this), lpXtAmt);

            lpXtAmt += reward;
            lpXt.burn(lpXtAmt);

            xtOutAmt = ((lpXtAmt * xtReserve) / lpXtTotalSupply).toUint128();
        }
        if (xtOutAmt >= xtReserve || ftOutAmt >= ftReserve) {
            revert TermMaxCurve.LiquidityIsZeroAfterTransaction();
        }
        uint sameProportionFt = (xtOutAmt * mConfig.initialLtv) /
            Constants.DECIMAL_BASE;
        if (sameProportionFt > ftOutAmt) {
            uint xtExcess = xtOutAmt -
                (ftOutAmt * Constants.DECIMAL_BASE) /
                mConfig.initialLtv;
            TradeParams memory tradeParams = TradeParams(
                xtExcess,
                ftReserve,
                xtReserve,
                _daysToMaturity(mConfig.maturity)
            );
            (, , mConfig.apr) = TermMaxCurve.sellNegXt(tradeParams, mConfig);
        } else if (sameProportionFt < ftOutAmt) {
            uint ftExcess = ftOutAmt - sameProportionFt;
            TradeParams memory tradeParams = TradeParams(
                ftExcess,
                ftReserve,
                xtReserve,
                _daysToMaturity(mConfig.maturity)
            );
            (, , mConfig.apr) = TermMaxCurve.sellNegFt(tradeParams, mConfig);
        }
        if (ftOutAmt > 0) {
            ft.transfer(caller, ftOutAmt);
        }
        if (xtOutAmt > 0) {
            xt.transfer(caller, xtOutAmt);
        }
        _config.apr = mConfig.apr;
        emit WithdrawLP(
            caller,
            lpFtAmt.toUint128(),
            lpXtAmt.toUint128(),
            ftOutAmt,
            xtOutAmt,
            mConfig.apr
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyFt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, ft, underlyingAmtIn, minTokenOut);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, xt, underlyingAmtIn, minTokenOut);
    }

    function _buyToken(
        address caller,
        IMintableERC20 token,
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) internal returns (uint256 netOut) {
        // Get old reserves
        uint ftReserve = ft.balanceOf(address(this));
        uint xtReserve = xt.balanceOf(address(this));
        MarketConfig memory mConfig = _config;
        TradeParams memory tradeParams = TradeParams(
            underlyingAmtIn,
            ftReserve,
            xtReserve,
            _daysToMaturity(mConfig.maturity)
        );

        uint feeAmt;
        // add new lituidity
        _addLiquidity(caller, underlyingAmtIn, mConfig.initialLtv);
        if (token == ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.buyFt(
                tradeParams,
                mConfig
            );
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.lendFeeRatio,
                mConfig.initialLtv
            );
            feeAmt = feeAmt.max(
                (underlyingAmtIn * mConfig.minNLendFeeR) /
                    Constants.DECIMAL_BASE
            );
            // Fee to prootocol
            feeAmt = _tranferFeeToTreasurer(
                mConfig.treasurer,
                feeAmt,
                mConfig.protocolFeeRatio
            );
            uint finalFtReserve;
            (finalFtReserve, , mConfig.apr) = TermMaxCurve.buyNegFt(
                TradeParams(
                    feeAmt,
                    newFtReserve,
                    newXtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );

            uint ftCurrentReserve = ft.balanceOf(address(this));
            netOut = ftCurrentReserve - finalFtReserve;
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.buyXt(
                tradeParams,
                mConfig
            );
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.borrowFeeRatio,
                mConfig.initialLtv
            );
            feeAmt = feeAmt.max(
                (underlyingAmtIn * mConfig.minNBorrowFeeR) /
                    Constants.DECIMAL_BASE
            );
            // Fee to prootocol
            feeAmt = _tranferFeeToTreasurer(
                mConfig.treasurer,
                feeAmt,
                mConfig.protocolFeeRatio
            );
            uint finalXtReserve;
            (, finalXtReserve, mConfig.apr) = TermMaxCurve.buyNegXt(
                TradeParams(
                    feeAmt,
                    newFtReserve,
                    newXtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );
            uint xtCurrentReserve = xt.balanceOf(address(this));
            netOut = xtCurrentReserve - finalXtReserve;
        }

        if (netOut < minTokenOut) {
            revert UnexpectedAmount(minTokenOut, netOut.toUint128());
        }
        token.transfer(caller, netOut);
        // _lock_fee
        _lockFee(feeAmt, mConfig.lockingPercentage, mConfig.initialLtv);
        _config.apr = mConfig.apr;
        emit BuyToken(
            caller,
            token,
            underlyingAmtIn,
            minTokenOut,
            netOut.toUint128(),
            feeAmt.toUint128(),
            mConfig.apr
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _sellToken(msg.sender, ft, ftAmtIn, minUnderlyingOut);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _sellToken(msg.sender, xt, xtAmtIn, minUnderlyingOut);
    }

    function _sellToken(
        address caller,
        IMintableERC20 token,
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut
    ) internal returns (uint256 netOut) {
        // Get old reserves
        uint ftReserve = ft.balanceOf(address(this));
        uint xtReserve = xt.balanceOf(address(this));

        token.transferFrom(caller, address(this), tokenAmtIn);

        MarketConfig memory mConfig = _config;
        TradeParams memory tradeParams = TradeParams(
            tokenAmtIn,
            ftReserve,
            xtReserve,
            _daysToMaturity(mConfig.maturity)
        );
        uint feeAmt;
        if (token == ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.sellFt(
                tradeParams,
                mConfig
            );
            netOut = xtReserve - newXtReserve;
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.borrowFeeRatio,
                mConfig.initialLtv
            );
            feeAmt = feeAmt.max(
                (netOut * mConfig.minNBorrowFeeR) / Constants.DECIMAL_BASE
            );
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.sellXt(
                tradeParams,
                mConfig
            );
            netOut = tokenAmtIn + xtReserve - newXtReserve;
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.lendFeeRatio,
                mConfig.initialLtv
            );
            feeAmt = feeAmt.max(
                (netOut * mConfig.minNLendFeeR) / Constants.DECIMAL_BASE
            );
        }
        netOut -= feeAmt;
        if (netOut < minUnderlyingOut) {
            revert UnexpectedAmount(minUnderlyingOut, netOut.toUint128());
        }
        // Fee to prootocol
        feeAmt = _tranferFeeToTreasurer(
            mConfig.treasurer,
            feeAmt,
            mConfig.protocolFeeRatio
        );

        ft.burn((netOut * mConfig.initialLtv) / Constants.DECIMAL_BASE);
        xt.burn(netOut);
        _lockFee(feeAmt, mConfig.lockingPercentage, mConfig.initialLtv);

        underlying.transfer(caller, netOut);
        _config.apr = mConfig.apr;
        emit SellToken(
            caller,
            token,
            tokenAmtIn,
            minUnderlyingOut,
            netOut.toUint128(),
            feeAmt.toUint128(),
            mConfig.apr
        );
    }

    function redeemFtAndXtToUnderlying(
        uint256 underlyingAmt
    ) external override nonReentrant isOpen {
        _redeemFtAndXtToUnderlying(msg.sender, underlyingAmt);
    }

    function _redeemFtAndXtToUnderlying(
        address caller,
        uint256 underlyingAmt
    ) internal {
        uint ftAmt = (underlyingAmt * _config.initialLtv) /
            Constants.DECIMAL_BASE;
        ft.transferFrom(caller, address(this), ftAmt);
        xt.transferFrom(caller, address(this), underlyingAmt);
        ft.burn(ftAmt);
        xt.burn(underlyingAmt);
        underlying.transfer(caller, underlyingAmt);

        emit RemoveLiquidity(caller, underlyingAmt);
    }

    /// @notice Lock up a portion of the transaction fee and release it slowly in the later stage
    function _lockFee(
        uint256 feeAmount,
        uint256 lockingPercentage,
        uint256 initialLtv
    ) internal {
        uint feeToLock = (feeAmount *
            lockingPercentage +
            Constants.DECIMAL_BASE -
            1) / Constants.DECIMAL_BASE;
        uint ftAmount = (feeToLock * initialLtv) / Constants.DECIMAL_BASE;

        uint lpFtAmt = TermMaxCurve.calculateLpOut(
            ftAmount,
            ft.balanceOf(address(this)) - ftAmount,
            lpFt.totalSupply()
        );
        lpFt.mint(address(this), lpFtAmt);

        uint lpXtAmt = TermMaxCurve.calculateLpOut(
            feeToLock,
            xt.balanceOf(address(this)) - feeToLock,
            lpXt.totalSupply()
        );
        lpXt.mint(address(this), lpXtAmt);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function leverageByXt(
        address receiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) external override isOpen nonReentrant returns (uint256 gtId) {
        return _leverageByXt(msg.sender, receiver, xtAmt, callbackData);
    }

    function _leverageByXt(
        address caller,
        address receiver,
        uint128 xtAmt,
        bytes calldata callbackData
    ) internal returns (uint256 gtId) {
        xt.transferFrom(caller, address(this), xtAmt);

        // 1 xt -> 1 underlying raised
        // Debt 1 * initialLtv round up
        uint128 debt = ((xtAmt *
            _config.initialLtv +
            Constants.DECIMAL_BASE -
            1) / Constants.DECIMAL_BASE).toUint128();

        // Send debt to borrower
        underlying.transfer(caller, debt);
        // Callback function
        bytes memory collateralData = IFlashLoanReceiver(caller)
            .executeOperation(receiver, underlying, debt, callbackData);

        // Mint GT
        gtId = gt.mint(caller, receiver, debt, collateralData);

        xt.burn(xtAmt);

        emit MintGt(caller, receiver, gtId, debt, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function issueFt(
        uint128 debt,
        bytes calldata collateralData
    )
        external
        override
        isOpen
        nonReentrant
        returns (uint256 gtId, uint128 ftOutAmt)
    {
        return _issueFt(msg.sender, debt, collateralData);
    }

    function _issueFt(
        address caller,
        uint128 debt,
        bytes calldata collateralData
    ) internal returns (uint256 gtId, uint128 ftOutAmt) {
        // Mint GT
        gtId = gt.mint(caller, caller, debt, collateralData);

        MarketConfig memory mConfig = _config;
        uint128 issueFee = ((debt * mConfig.issueFtFeeRatio) /
            Constants.DECIMAL_BASE).toUint128();
        // Mint ft amount = debt amount, send issueFee to treasurer and other to caller
        ft.mint(mConfig.treasurer, issueFee);
        ftOutAmt = debt - issueFee;
        ft.mint(caller, ftOutAmt);

        emit IssueFt(caller, gtId, debt, ftOutAmt, issueFee, collateralData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function redeem(
        uint256[4] calldata amountArray
    ) external virtual override nonReentrant {
        _redeem(msg.sender, amountArray);
    }

    // function redeemByPermit(
    //     address caller,
    //     uint256[4] calldata amountArray,
    //     uint256[4] calldata deadlineArray,
    //     uint8[4] calldata vArray,
    //     bytes32[4] calldata rArrray,
    //     bytes32[4] calldata sArray
    // ) external virtual override nonReentrant {
    //     IMintableERC20[4] memory permitTokens = [lpFt, lpXt, ft, xt];
    //     for (uint i = 0; i < amountArray.length; ++i) {
    //         if (amountArray[i] > 0) {
    //             permitTokens[i].permit(
    //                 sender,
    //                 address(this),
    //                 amountArray[i],
    //                 deadlineArray[i],
    //                 vArray[i],
    //                 rArrray[i],
    //                 sArray[i]
    //             );
    //         }
    //     }
    //     _redeem(sender, amountArray);
    // }

    function _redeem(address caller, uint256[4] calldata amountArray) internal {
        MarketConfig memory mConfig = _config;
        {
            uint liquidationDeadline = gt.liquidatable()
                ? mConfig.maturity + Constants.LIQUIDATION_WINDOW
                : mConfig.maturity;
            if (block.timestamp < liquidationDeadline) {
                revert CanNotRedeemBeforeFinalLiquidationDeadline(
                    liquidationDeadline
                );
            }
        }
        // Burn all lp tokens owned by this contract after maturity to release all reward
        if (!mConfig.rewardIsDistributed) {
            _distributeAllReward();
            _config.rewardIsDistributed = true;
        }

        // k = (1 - initalLtv) * DECIMAL_BASE
        uint k = Constants.DECIMAL_BASE - mConfig.initialLtv;
        // All points = ftSupply + xtSupply * (1 - initalLtv) = ftSupply + xtSupply * k / DECIMAL_BASE
        uint allPoints = ft.totalSupply() *
            Constants.DECIMAL_BASE +
            xt.totalSupply() *
            k;

        uint userPoint;
        // uint fee;
        {
            // Calculate lp tokens output
            uint lpFtAmt = amountArray[2];
            if (lpFtAmt > 0) {
                lpFt.transferFrom(caller, address(this), lpFtAmt);
                uint lpFtTotalSupply = lpFt.totalSupply();
                uint ftReserve = ft.balanceOf(address(this));
                uint ftPoint = (lpFtAmt * ftReserve * Constants.DECIMAL_BASE) /
                    lpFtTotalSupply;
                userPoint += ftPoint;
                lpFt.burn(lpFtAmt);
                ft.burn(ftPoint / Constants.DECIMAL_BASE);
            }
            uint lpXtAmt = amountArray[3];
            if (lpXtAmt > 0) {
                lpXt.transferFrom(caller, address(this), lpXtAmt);
                uint lpXtTotalSupply = lpXt.totalSupply();
                uint xtReserve = xt.balanceOf(address(this));
                uint xtPoint = (lpXtAmt * xtReserve * k) / lpXtTotalSupply;
                userPoint += xtPoint;
                lpXt.burn(lpXtAmt);
                xt.burn(xtPoint / k);
            }
        }

        {
            uint ftAmt = amountArray[0];
            if (ftAmt > 0) {
                ft.transferFrom(caller, address(this), ftAmt);
                userPoint += ftAmt * Constants.DECIMAL_BASE;
                ft.burn(ftAmt);
            }
            uint xtAmt = amountArray[1];
            if (xtAmt > 0) {
                xt.transferFrom(caller, address(this), xtAmt);
                userPoint += xtAmt * k;
                xt.burn(xtAmt);
            }
        }
        // The proportion that user will get how many underlying and collateral when do redeem
        uint proportion = (userPoint * Constants.DECIMAL_BASE_SQ) / allPoints;
        bytes memory deliveryData = gt.delivery(proportion, caller);
        // Transfer underlying output
        uint redeemmingAmt = (underlying.balanceOf(address(this)) *
            proportion) / Constants.DECIMAL_BASE_SQ;
        uint feeAmt;
        if (mConfig.redeemFeeRatio > 0) {
            feeAmt =
                (redeemmingAmt * mConfig.redeemFeeRatio) /
                Constants.DECIMAL_BASE;
            underlying.transfer(mConfig.treasurer, feeAmt);
            redeemmingAmt -= feeAmt;
        }
        underlying.transfer(caller, redeemmingAmt);
        emit Redeem(
            caller,
            proportion.toUint128(),
            redeemmingAmt.toUint128(),
            feeAmt.toUint128(),
            deliveryData
        );
    }

    /// @notice Release all locked rewards
    function _distributeAllReward() internal {
        uint lpFtBalance = lpFt.balanceOf(address(this));
        uint lpXtBalance = lpXt.balanceOf(address(this));
        if (lpFtBalance > 0) {
            lpFt.burn(lpFtBalance);
        }
        if (lpXtBalance > 0) {
            lpXt.burn(lpXtBalance);
        }
        // Burn all ft in gt
        uint amount = ft.balanceOf(address(gt));
        ft.transferFrom(address(gt), address(this), amount);
        ft.burn(amount);
    }

    function _tranferFeeToTreasurer(
        address treasurer,
        uint256 totalFee,
        uint32 protocolFeeRatio
    ) internal returns (uint256 remainningFee) {
        uint feeToProtocol = (totalFee * protocolFeeRatio) /
            Constants.DECIMAL_BASE;
        underlying.transfer(treasurer, feeToProtocol);
        remainningFee = totalFee - feeToProtocol;
    }

    /// @notice Suspension of market trading
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Open Market Trading
    function unpause() external onlyOwner {
        _unpause();
    }
}
