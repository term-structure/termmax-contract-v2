// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {IMintableERC20} from "./tokens/IMintableERC20.sol";
import {IGearingNft} from "./tokens/IGearingNft.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {TermMaxCurve} from "./lib/TermMaxCurve.sol";
import {Constants} from "./lib/Constants.sol";
import {TermMaxStorage} from "./storage/TermMaxStorage.sol";

contract TermMaxMarket is ITermMaxMarket, ReentrancyGuard, Ownable {
    using SafeCast for uint256;
    using SafeCast for int256;

    TermMaxStorage.MarketConfig _config;
    address public collateral;
    IERC20 public cash;
    IMintableERC20 public ft;
    IMintableERC20 public xt;
    IMintableERC20 public lpFt;
    IMintableERC20 public lpXt;
    IGearingNft public gNft;

    constructor(
        address collateral_,
        IERC20 cash_,
        uint64 openTime_,
        uint64 maturity_
    ) Ownable(msg.sender) {
        if (
            openTime_ < block.timestamp ||
            maturity_ < block.timestamp + Constants.SECONDS_IN_MOUNTH
        ) {
            revert InvalidTime(openTime_, maturity_);
        }
        if (address(collateral_) == address(cash_)) {
            revert CollateralCanNotEqualCash();
        }
        cash = cash_;
        collateral = collateral_;
    }

    modifier isOpen() {
        if (block.timestamp < _config.openTime) {
            revert MarketIsNotOpen();
        }
        if (block.timestamp >= _config.maturity) {
            revert MarketWasClosed();
        }
        _;
    }

    function config()
        public
        view
        override
        returns (TermMaxStorage.MarketConfig memory)
    {
        return _config;
    }

    function tokens()
        external
        view
        override
        returns (
            IMintableERC20 _ft,
            IMintableERC20 _xt,
            IMintableERC20 _lpFt,
            IMintableERC20 _lpXt,
            IGearingNft _gNft,
            address _collateral,
            IERC20 _cash
        )
    {
        return (ft, xt, lpFt, lpXt, gNft, collateral, cash);
    }

    function initialize(
        IMintableERC20[4] memory tokens_,
        IGearingNft gNft_,
        TermMaxStorage.MarketConfig memory config_
    ) external override onlyOwner {
        if (_config.initialLtv != 0) {
            revert MarketHasBeenInitialized();
        }
        if (!config_.liquidatable && !config_.deliverable) {
            revert MarketMustHasLiquidationStrategy();
        }
        if (
            config_.gamma > Constants.DECIMAL_BASE ||
            config_.initialLtv > Constants.DECIMAL_BASE ||
            config_.lendFeeRatio > Constants.DECIMAL_BASE ||
            config_.borrowFeeRatio > Constants.DECIMAL_BASE ||
            int(config_.apy).toUint256() > Constants.DECIMAL_BASE ||
            config_.protocolFeeRatio > Constants.DECIMAL_BASE
        ) {
            revert NumeratorMustLessThanBasicDecimals();
        }

        ft = tokens_[0];
        xt = tokens_[1];
        lpFt = tokens_[2];
        lpXt = tokens_[3];
        gNft = gNft_;

        _config = config_;
    }

    // input cash
    // output lp tokens
    function provideLiquidity(
        uint256 cashAmt
    )
        external
        isOpen
        nonReentrant
        returns (uint128 lpXtOutAmt, uint128 lpFtOutAmt)
    {
        (lpXtOutAmt, lpFtOutAmt) = _provideLiquidity(msg.sender, cashAmt);
    }

    function _provideLiquidity(
        address sender,
        uint256 cashAmt
    ) internal returns (uint128 lpXtOutAmt, uint128 lpFtOutAmt) {
        uint ftReserve = ft.balanceOf(address(this));
        uint lpFtTotalSupply = lpFt.totalSupply();

        uint xtReserve = xt.balanceOf(address(this));
        uint lpXtTotalSupply = lpXt.totalSupply();
        (uint128 ftMintedAmt, uint128 xtMintedAmt) = _addLiquidity(
            sender,
            cashAmt,
            _config.initialLtv
        );

        lpFtOutAmt = TermMaxCurve
            ._calculateLpOut(ftMintedAmt, ftReserve, lpFtTotalSupply)
            .toUint128();

        lpXtOutAmt = TermMaxCurve
            ._calculateLpOut(xtMintedAmt, xtReserve, lpXtTotalSupply)
            .toUint128();
        lpXt.mint(sender, lpXtOutAmt);
        lpFt.mint(sender, lpFtOutAmt);

        emit ProvideLiquidity(sender, cashAmt, lpFtOutAmt, lpXtOutAmt);
    }

    function _addLiquidity(
        address sender,
        uint256 cashAmt,
        uint256 ltv
    ) internal returns (uint128 ftMintedAmt, uint128 xtMintedAmt) {
        cash.transferFrom(sender, address(this), cashAmt);

        ftMintedAmt = ((cashAmt * ltv) / Constants.DECIMAL_BASE).toUint128();
        xtMintedAmt = cashAmt.toUint128();
        // Mint tokens to this
        ft.mint(address(this), ftMintedAmt);
        xt.mint(address(this), xtMintedAmt);

        emit AddLiquidity(sender, cashAmt, ftMintedAmt, xtMintedAmt);
    }

    function _daysToMaturity(
        uint maturity
    ) internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (maturity - block.timestamp + Constants.SECONDS_IN_DAY - 1) /
            Constants.SECONDS_IN_DAY;
    }

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
        address sender,
        uint256 lpFtAmt,
        uint256 lpXtAmt
    ) internal returns (uint128 ftOutAmt, uint128 xtOutAmt) {
        uint lpFtTotalSupply;
        uint lpXtTotalSupply;
        TermMaxStorage.MarketConfig memory mConfig = _config;
        // calculate reward
        if (lpFtAmt > 0) {
            lpFt.transferFrom(sender, address(this), lpFtAmt);

            lpFtTotalSupply = lpFt.totalSupply();
            uint reward = TermMaxCurve._calculateLpReward(
                block.timestamp,
                mConfig.openTime,
                mConfig.maturity,
                lpFtTotalSupply,
                lpFtAmt,
                lpFt.balanceOf(address(this))
            );
            lpFtAmt += reward;
            lpFt.burn(lpFtAmt);
        }
        if (lpXtAmt > 0) {
            lpXt.transferFrom(sender, address(this), lpXtAmt);

            lpXtTotalSupply = lpXt.totalSupply();
            uint reward = TermMaxCurve._calculateLpReward(
                block.timestamp,
                mConfig.openTime,
                mConfig.maturity,
                lpXtTotalSupply,
                lpXtAmt,
                lpXt.balanceOf(address(this))
            );
            lpXtAmt += reward;
            lpXt.burn(lpXtAmt);
        }
        // get token reserves
        uint ftReserve = ft.balanceOf(address(this));
        ftOutAmt = ((lpFtAmt * ftReserve) / lpFtTotalSupply).toUint128();
        uint xtReserve = xt.balanceOf(address(this));
        xtOutAmt = ((lpXtAmt * xtReserve) / lpXtTotalSupply).toUint128();

        uint sameProportionFt = (xtOutAmt * mConfig.initialLtv) /
            Constants.DECIMAL_BASE;
        if (sameProportionFt > ftOutAmt) {
            uint xtExcess = ((sameProportionFt - ftOutAmt) *
                Constants.DECIMAL_BASE) / mConfig.initialLtv;
            TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve
                .TradeParams(
                    xtExcess,
                    ftReserve,
                    xtReserve,
                    _daysToMaturity(mConfig.maturity)
                );
            (, , mConfig.apy) = TermMaxCurve._sellNegXt(tradeParams, mConfig);
        } else if (sameProportionFt < ftOutAmt) {
            uint ftExcess = ftOutAmt - sameProportionFt;
            TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve
                .TradeParams(
                    ftExcess,
                    ftReserve,
                    xtReserve,
                    _daysToMaturity(mConfig.maturity)
                );
            (, , mConfig.apy) = TermMaxCurve._sellNegFt(tradeParams, mConfig);
        }
        if (ftOutAmt > 0) {
            xt.transfer(sender, ftOutAmt);
        }
        if (xtOutAmt > 0) {
            ft.transfer(sender, xtOutAmt);
        }
        _config.apy = mConfig.apy;
        emit WithdrawLP(
            sender,
            lpFtAmt.toUint128(),
            lpXtAmt.toUint128(),
            ftOutAmt,
            xtOutAmt,
            mConfig.apy
        );
    }

    function buyFt(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, ft, cashAmtIn, minTokenOut);
    }

    function buyXt(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, xt, cashAmtIn, minTokenOut);
    }

    function _buyToken(
        address sender,
        IMintableERC20 token,
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) internal returns (uint256 netOut) {
        // Get old reserves
        uint ftReserve = ft.balanceOf(address(this));
        uint xtReserve = xt.balanceOf(address(this));
        TermMaxStorage.MarketConfig memory mConfig = _config;
        TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve.TradeParams(
            cashAmtIn,
            ftReserve,
            xtReserve,
            _daysToMaturity(mConfig.maturity)
        );

        uint feeAmt;
        // add new lituidity
        _addLiquidity(sender, cashAmtIn, mConfig.initialLtv);
        if (token == ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apy) = TermMaxCurve._buyFt(
                tradeParams,
                mConfig
            );
            // calculate fee
            feeAmt = TermMaxCurve._calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.lendFeeRatio,
                mConfig.initialLtv
            );
            // Fee to prootocol
            feeAmt = _tranferFeeToTreasure(
                mConfig.treasurer,
                feeAmt,
                mConfig.protocolFeeRatio
            );
            uint finalFtReserve;
            (finalFtReserve, , mConfig.apy) = TermMaxCurve._buyNegFt(
                TermMaxCurve.TradeParams(
                    feeAmt,
                    ftReserve,
                    xtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );

            uint ypCurrentReserve = ft.balanceOf(address(this));
            netOut = ypCurrentReserve - finalFtReserve;
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apy) = TermMaxCurve._buyXt(
                tradeParams,
                mConfig
            );
            // calculate fee
            feeAmt = TermMaxCurve._calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.borrowFeeRatio,
                mConfig.initialLtv
            );
            // Fee to prootocol
            feeAmt = _tranferFeeToTreasure(
                mConfig.treasurer,
                feeAmt,
                mConfig.protocolFeeRatio
            );
            uint finalXtReserve;
            (finalXtReserve, , mConfig.apy) = TermMaxCurve._buyNegXt(
                TermMaxCurve.TradeParams(
                    feeAmt,
                    ftReserve,
                    xtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );
            uint yaCurrentReserve = xt.balanceOf(address(this));
            netOut = yaCurrentReserve - finalXtReserve;
        }

        if (netOut < minTokenOut) {
            revert UnexpectedAmount(
                sender,
                token,
                minTokenOut,
                netOut.toUint128()
            );
        }
        token.transfer(sender, netOut);
        // _lock_fee
        _lockFee(feeAmt, mConfig.lockingFeeRatio, mConfig.initialLtv);
        _config.apy = mConfig.apy;
        emit BuyToken(
            sender,
            token,
            minTokenOut,
            netOut.toUint128(),
            mConfig.apy
        );
    }

    function _sellToken(
        address sender,
        IMintableERC20 token,
        uint128 tokenAmtIn,
        uint128 minCashOut
    ) internal returns (uint256 netOut) {
        token.transferFrom(sender, address(this), tokenAmtIn);
        // Get old reserves
        uint ftReserve = ft.balanceOf(address(this));
        uint xtReserve = xt.balanceOf(address(this));
        TermMaxStorage.MarketConfig memory mConfig = _config;
        TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve.TradeParams(
            tokenAmtIn,
            ftReserve,
            xtReserve,
            _daysToMaturity(mConfig.maturity)
        );
        uint feeAmt;
        if (token == ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apy) = TermMaxCurve._sellFt(
                tradeParams,
                mConfig
            );
            netOut = xtReserve - newFtReserve;
            // calculate fee
            feeAmt = TermMaxCurve._calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.borrowFeeRatio,
                mConfig.initialLtv
            );
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apy) = TermMaxCurve._sellXt(
                tradeParams,
                mConfig
            );
            netOut = tokenAmtIn + xtReserve - newFtReserve;
            // calculate fee
            feeAmt = TermMaxCurve._calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.lendFeeRatio,
                mConfig.initialLtv
            );
        }
        netOut -= feeAmt;
        if (netOut < minCashOut) {
            revert UnexpectedAmount(
                sender,
                token,
                minCashOut,
                netOut.toUint128()
            );
        }
        // Fee to prootocol
        feeAmt = _tranferFeeToTreasure(
            mConfig.treasurer,
            feeAmt,
            mConfig.protocolFeeRatio
        );
        _lockFee(feeAmt, mConfig.lockingFeeRatio, mConfig.initialLtv);
        token.burn(tokenAmtIn);
        cash.transfer(sender, netOut);
        _config.apy = mConfig.apy;
        emit SellToken(
            sender,
            token,
            minCashOut,
            netOut.toUint128(),
            mConfig.apy
        );
    }

    function _lockFee(
        uint256 feeAmount,
        uint256 lockingFeeRatio,
        uint256 initialLtv
    ) internal {
        uint feeToLock = (feeAmount *
            lockingFeeRatio +
            Constants.DECIMAL_BASE -
            1) / Constants.DECIMAL_BASE;
        uint ypAmount = (feeToLock * initialLtv) / Constants.DECIMAL_BASE;

        uint lpFtAmt = TermMaxCurve._calculateLpOut(
            ypAmount,
            ft.balanceOf(address(this)) - ypAmount,
            lpFt.totalSupply()
        );
        lpFt.mint(address(this), lpFtAmt);

        uint lpXtAmt = TermMaxCurve._calculateLpOut(
            feeToLock,
            xt.balanceOf(address(this)) - feeToLock,
            lpXt.totalSupply()
        );
        lpXt.mint(address(this), lpXtAmt);
    }

    function mintGNft(
        uint128 xtAmt,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external override isOpen nonReentrant returns (uint256 nftId) {
        return _mintGNft(msg.sender, collateralData, xtAmt, callbackData);
    }

    function _mintGNft(
        address sender,
        bytes memory collateralData,
        uint128 xtAmt,
        bytes calldata callbackData
    ) internal returns (uint256 nftId) {
        xt.transferFrom(sender, address(this), xtAmt);

        if (xtAmt < _config.minLeveragedXt) {
            revert XTAmountTooLittle(sender, xtAmt, collateralData);
        }
        uint128 debt = (xtAmt * _config.initialLtv) / Constants.DECIMAL_BASE;

        // Send debt to borrower
        cash.transfer(sender, debt);
        // Callback function
        if (
            !IFlashLoanReceiver(sender).executeOperation(
                sender,
                cash,
                debt,
                callbackData
            )
        ) {
            revert MintGNFTFailedCallback(sender, xtAmt, debt, callbackData);
        }

        // Mint G-NFT
        nftId = gNft.mint(sender, debt, collateralData);

        emit MintGNft(sender, nftId, debt, collateralData);
    }

    function lever(
        uint128 debtAmt,
        bytes calldata collateralData
    ) external override isOpen nonReentrant returns (uint256 nftId) {
        return _lever(msg.sender, debtAmt, collateralData);
    }

    function _lever(
        address sender,
        uint128 debtAmt,
        bytes calldata collateralData
    ) internal returns (uint256 nftId) {
        if (debtAmt < _config.minLeveredFt) {
            revert XTAmountTooLittle(sender, debtAmt, collateralData);
        }
        // Mint G-NFT
        nftId = gNft.mint(sender, debtAmt, collateralData);

        ft.mint(sender, debtAmt);

        emit MintGNft(sender, nftId, debtAmt, collateralData);
    }

    // use cash to repayDebt
    function repayGNft(
        uint256 nftId,
        uint128 repayAmt
    ) external override isOpen nonReentrant {
        _repayGNft(msg.sender, nftId, repayAmt);
    }

    function _repayGNft(
        address sender,
        uint256 nftId,
        uint128 repayAmt
    ) internal {
        gNft.repay(sender, nftId, repayAmt);
        cash.transferFrom(sender, address(this), repayAmt);
        emit RepayGNft(sender, nftId, repayAmt, false);
    }

    // use yp to deregister debt
    function deregisterGNft(
        uint256 nftId
    ) external override isOpen nonReentrant {
        _deregisterGNft(msg.sender, nftId);
    }

    function _deregisterGNft(address sender, uint256 nftId) internal {
        uint128 debtAmt = gNft.deregister(sender, nftId);
        ft.transferFrom(sender, address(this), debtAmt);
        emit DeregisterGNft(sender, nftId, debtAmt);
    }

    function liquidateGNft(uint256 nftId) external override nonReentrant {
        _liquidateGNft(msg.sender, nftId);
    }

    function _liquidateGNft(address liquidator, uint256 nftId) internal {
        TermMaxStorage.MarketConfig memory mConfig = _config;
        if (!mConfig.liquidatable) {
            revert MarketDoNotSupportLiquidation();
        }
        if (mConfig.deliverable && block.timestamp >= mConfig.maturity) {
            revert CanNotLiquidateAfterMaturity();
        }
        uint128 debtAmt = gNft.liquidate(nftId, liquidator);

        cash.transferFrom(liquidator, address(this), debtAmt);

        emit LiquidateGNft(liquidator, nftId, debtAmt);
    }

    function redeem() external virtual override nonReentrant {
        _redeem(msg.sender);
    }

    function _redeem(address sender) internal {
        TermMaxStorage.MarketConfig memory mConfig = _config;
        if (block.timestamp < mConfig.maturity) {
            revert CanNotRedeemBeforeMaturity();
        }
        // Burn all lp tokens owned by this contract after maturity to release all reward
        if (!mConfig.rewardIsDistributed) {
            _distributeAllReward();
        }
        // k = (1 - initalLtv) * DECIMAL_BASE
        uint k = Constants.DECIMAL_BASE - mConfig.initialLtv;
        uint userPoint;
        {
            // Calculate lp tokens output
            uint lpFtAmt = lpFt.balanceOf(sender);
            if (lpFtAmt > 0) {
                lpFt.transferFrom(sender, address(this), lpFtAmt);
                uint lpFtTotalSupply = lpFt.totalSupply();
                uint ftReserve = ft.balanceOf(address(this));
                userPoint += (lpFtAmt * ftReserve) / lpFtTotalSupply;
                lpFt.burn(lpFtAmt);
            }
            uint lpXtAmt = lpXt.balanceOf(sender);
            if (lpXtAmt > 0) {
                lpXt.transferFrom(sender, address(this), lpXtAmt);
                uint lpXtTotalSupply = lpXt.totalSupply();
                uint xtReserve = xt.balanceOf(address(this));
                uint xtAmt = (lpXtAmt * xtReserve) / lpXtTotalSupply;
                userPoint += (xtAmt * k) / Constants.DECIMAL_BASE;
                lpFt.burn(lpXtAmt);
            }
        }
        // All points = ypSupply + yaSupply * (1 - initalLtv) = ypSupply * k / DECIMAL_BASE
        uint allPoints = ft.totalSupply() +
            (xt.totalSupply() * k) /
            Constants.DECIMAL_BASE;
        {
            uint ftAmt = ft.balanceOf(sender);
            if (ftAmt > 0) {
                ft.transferFrom(sender, address(this), ftAmt);
                userPoint += ftAmt;
                ft.burn(ftAmt);
            }
            uint xtAmt = xt.balanceOf(sender);
            if (xtAmt > 0) {
                xt.transferFrom(sender, address(this), xtAmt);
                userPoint += (xtAmt * k) / Constants.DECIMAL_BASE;
                xt.burn(xtAmt);
            }
        }

        // The ratio that user will get how many cash and collateral when do redeem
        uint ratio = (userPoint * Constants.DECIMAL_BASE) / allPoints;
        bytes memory deliveryData = gNft.delivery(ratio, sender);
        // Transfer cash output
        uint cashAmt = (cash.balanceOf(address(this)) * ratio) /
            Constants.DECIMAL_BASE;
        cash.transfer(sender, cashAmt);
        emit Redeem(
            sender,
            ratio.toUint128(),
            cashAmt.toUint128(),
            deliveryData
        );
    }

    function _transferAllBalance(
        IERC20 token,
        address from,
        address to
    ) internal returns (uint256 amount) {
        amount = token.balanceOf(from);
        if (amount > 0) {
            token.transferFrom(from, to, amount);
        }
    }

    function _distributeAllReward() internal {
        uint lpFtBalance = lpFt.balanceOf(address(this));
        uint lpXtBalance = lpXt.balanceOf(address(this));
        if (lpFtBalance > 0) {
            lpFt.burn(lpFtBalance);
        }
        if (lpXtBalance > 0) {
            lpXt.burn(lpXtBalance);
        }
    }

    function _tranferFeeToTreasure(
        address treasurer,
        uint256 totalFee,
        uint32 protocolFeeRatio
    ) internal returns (uint256 feeToMarket) {
        uint feeToProtocol = (totalFee * protocolFeeRatio) /
            Constants.DECIMAL_BASE;
        cash.transfer(treasurer, feeToProtocol);
        feeToMarket = totalFee - feeToProtocol;
    }

    function _transferToken(IERC20 token, address to, uint256 value) internal {
        _transferTokenFrom(token, address(this), to, value);
    }

    function _transferTokenFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        if ((from == address(this) && to == address(this)) || value == 0) {
            return;
        }
        token.transferFrom(from, to, value);
    }
}
