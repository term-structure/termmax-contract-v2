// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITermMaxMarket} from "./ITermMaxMarket.sol";
import {IMintableERC20} from "./tokens/IMintableERC20.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {TermMaxCurve} from "./lib/TermMaxCurve.sol";
import {Constants} from "./lib/Constants.sol";
import "./storage/TermMaxStorage.sol";

contract TermMaxMarket is ITermMaxMarket, ReentrancyGuard, Ownable, Pausable {
    using SafeCast for uint256;
    using SafeCast for int256;

    MarketConfig _config;
    address public collateral;
    IERC20 public underlying;
    IMintableERC20 public ft;
    IMintableERC20 public xt;
    IMintableERC20 public lpFt;
    IMintableERC20 public lpXt;
    IGearingToken public gt;

    constructor(
        address collateral_,
        IERC20 underlying_,
        uint64 openTime_,
        uint64 maturity_
    ) Ownable(msg.sender) {
        if (openTime_ < block.timestamp || maturity_ < openTime_) {
            revert InvalidTime(openTime_, maturity_);
        }
        if (address(collateral_) == address(underlying_)) {
            revert CollateralCanNotEqualUnserlyinng();
        }
        underlying = underlying_;
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

    function config() public view override returns (MarketConfig memory) {
        return _config;
    }

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

    function initialize(
        IMintableERC20[4] memory tokens_,
        IGearingToken gt_,
        MarketConfig memory config_
    ) external override onlyOwner {
        if (address(ft) != address(0)) {
            revert MarketHasBeenInitialized();
        }

        ft = tokens_[0];
        xt = tokens_[1];
        lpFt = tokens_[2];
        lpXt = tokens_[3];
        gt = gt_;

        _config = config_;
    }

    function setFeeRatio(
        uint32 lendFeeRatio,
        uint32 minNLendFeeR,
        uint32 borrowFeeRatio,
        uint32 minNBorrowFeeR,
        uint32 redeemFeeRatio,
        uint32 leverfeeRatio,
        uint32 lockingPercentage,
        uint32 protocolFeeRatio
    ) external override onlyOwner isOpen {
        MarketConfig memory mConfig = _config;
        mConfig.lendFeeRatio = lendFeeRatio;
        mConfig.minNLendFeeR = minNLendFeeR;
        mConfig.borrowFeeRatio = borrowFeeRatio;
        mConfig.minNBorrowFeeR = minNBorrowFeeR;
        mConfig.redeemFeeRatio = redeemFeeRatio;
        mConfig.leverfeeRatio = leverfeeRatio;
        mConfig.lockingPercentage = lockingPercentage;
        mConfig.protocolFeeRatio = protocolFeeRatio;
        emit UpdateFeeRatio(
            lendFeeRatio,
            minNLendFeeR,
            borrowFeeRatio,
            minNBorrowFeeR,
            redeemFeeRatio,
            leverfeeRatio,
            lockingPercentage,
            protocolFeeRatio
        );
    }

    function setTreasurer(address treasurer) external onlyOwner {
        _config.treasurer = treasurer;
        gt.setTreasurer(treasurer);

        emit UpdateTreasurer(treasurer);
    }

    // input underlying
    // output lp tokens
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
        address sender,
        uint256 underlyingAmt
    ) internal returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt) {
        uint ftReserve = ft.balanceOf(address(this));
        uint lpFtTotalSupply = lpFt.totalSupply();

        uint xtReserve = xt.balanceOf(address(this));
        uint lpXtTotalSupply = lpXt.totalSupply();
        (uint128 ftMintedAmt, uint128 xtMintedAmt) = _addLiquidity(
            sender,
            underlyingAmt,
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

        emit ProvideLiquidity(sender, underlyingAmt, lpFtOutAmt, lpXtOutAmt);
    }

    function _addLiquidity(
        address sender,
        uint256 underlyingAmt,
        uint256 ltv
    ) internal returns (uint128 ftMintedAmt, uint128 xtMintedAmt) {
        underlying.transferFrom(sender, address(this), underlyingAmt);

        ftMintedAmt = ((underlyingAmt * ltv) / Constants.DECIMAL_BASE)
            .toUint128();
        xtMintedAmt = underlyingAmt.toUint128();
        // Mint tokens to this
        ft.mint(address(this), ftMintedAmt);
        xt.mint(address(this), xtMintedAmt);
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
        uint lpFtTotalSupply = lpFt.totalSupply();
        uint lpXtTotalSupply = lpXt.totalSupply();
        MarketConfig memory mConfig = _config;
        // calculate reward
        uint ftReserve = ft.balanceOf(address(this));
        if (lpFtAmt > 0) {
            uint reward = TermMaxCurve._calculateLpReward(
                block.timestamp,
                mConfig.openTime,
                mConfig.maturity,
                lpFtTotalSupply,
                lpFtAmt,
                lpFt.balanceOf(address(this))
            );
            lpFt.transferFrom(sender, address(this), lpFtAmt);
            lpFt.burn(lpFtAmt);

            lpFtAmt += reward;

            ftOutAmt = ((lpFtAmt * ftReserve) / lpFtTotalSupply).toUint128();
        }
        uint xtReserve = xt.balanceOf(address(this));
        if (lpXtAmt > 0) {
            uint reward = TermMaxCurve._calculateLpReward(
                block.timestamp,
                mConfig.openTime,
                mConfig.maturity,
                lpXtTotalSupply,
                lpXtAmt,
                lpXt.balanceOf(address(this))
            );
            lpXtAmt += reward;

            lpXt.transferFrom(sender, address(this), lpXtAmt);
            lpXt.burn(lpXtAmt);

            xtOutAmt = ((lpXtAmt * xtReserve) / lpXtTotalSupply).toUint128();
        }

        uint sameProportionFt = (xtOutAmt * mConfig.initialLtv) /
            Constants.DECIMAL_BASE;

        if (sameProportionFt > ftOutAmt) {
            uint xtExcess = ((sameProportionFt - ftOutAmt) *
                Constants.DECIMAL_BASE) / mConfig.initialLtv;
            TradeParams memory tradeParams = TradeParams(
                xtExcess,
                ftReserve,
                xtReserve,
                _daysToMaturity(mConfig.maturity)
            );
            (, , mConfig.apr) = TermMaxCurve._sellNegXt(tradeParams, mConfig);
        } else if (sameProportionFt < ftOutAmt) {
            uint ftExcess = ftOutAmt - sameProportionFt;
            TradeParams memory tradeParams = TradeParams(
                ftExcess,
                ftReserve,
                xtReserve,
                _daysToMaturity(mConfig.maturity)
            );
            (, , mConfig.apr) = TermMaxCurve._sellNegFt(tradeParams, mConfig);
        }
        if (ftOutAmt > 0) {
            ft.transfer(sender, ftOutAmt);
        }
        if (xtOutAmt > 0) {
            xt.transfer(sender, xtOutAmt);
        }
        _config.apr = mConfig.apr;
        emit WithdrawLP(
            sender,
            lpFtAmt.toUint128(),
            lpXtAmt.toUint128(),
            ftOutAmt,
            xtOutAmt,
            mConfig.apr
        );
    }

    function buyFt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, ft, underlyingAmtIn, minTokenOut);
    }

    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, xt, underlyingAmtIn, minTokenOut);
    }

    function _buyToken(
        address sender,
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
        _addLiquidity(sender, underlyingAmtIn, mConfig.initialLtv);
        if (token == ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve._buyFt(
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
            feeAmt = TermMaxCurve._max(
                feeAmt,
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
            (finalFtReserve, , mConfig.apr) = TermMaxCurve._buyNegFt(
                TradeParams(
                    feeAmt,
                    newFtReserve,
                    newXtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );

            uint ypCurrentReserve = ft.balanceOf(address(this));
            netOut = ypCurrentReserve - finalFtReserve;
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve._buyXt(
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
            feeAmt = TermMaxCurve._max(
                feeAmt,
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
            (, finalXtReserve, mConfig.apr) = TermMaxCurve._buyNegXt(
                TradeParams(
                    feeAmt,
                    newFtReserve,
                    newXtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );
            uint yaCurrentReserve = xt.balanceOf(address(this));
            netOut = yaCurrentReserve - finalXtReserve;
        }

        if (netOut < minTokenOut) {
            revert UnexpectedAmount(sender, minTokenOut, netOut.toUint128());
        }
        token.transfer(sender, netOut);
        // _lock_fee
        _lockFee(feeAmt, mConfig.lockingPercentage, mConfig.initialLtv);
        _config.apr = mConfig.apr;
        emit BuyToken(
            sender,
            token,
            minTokenOut,
            netOut.toUint128(),
            mConfig.apr
        );
    }

    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut
    ) external override returns (uint256 netOut) {
        netOut = _sellToken(msg.sender, ft, ftAmtIn, minUnderlyingOut);
    }

    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut
    ) external override returns (uint256 netOut) {
        netOut = _sellToken(msg.sender, xt, xtAmtIn, minUnderlyingOut);
    }

    function _sellToken(
        address sender,
        IMintableERC20 token,
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut
    ) internal returns (uint256 netOut) {
        // Get old reserves
        uint ftReserve = ft.balanceOf(address(this));
        uint xtReserve = xt.balanceOf(address(this));

        token.transferFrom(sender, address(this), tokenAmtIn);

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
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve._sellFt(
                tradeParams,
                mConfig
            );
            netOut = xtReserve - newXtReserve;
            // calculate fee
            feeAmt = TermMaxCurve._calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.borrowFeeRatio,
                mConfig.initialLtv
            );
            feeAmt = TermMaxCurve._max(
                feeAmt,
                (netOut * mConfig.minNBorrowFeeR) / Constants.DECIMAL_BASE
            );
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve._sellXt(
                tradeParams,
                mConfig
            );
            netOut = tokenAmtIn + xtReserve - newXtReserve;
            // calculate fee
            feeAmt = TermMaxCurve._calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                mConfig.lendFeeRatio,
                mConfig.initialLtv
            );
            feeAmt = TermMaxCurve._max(
                feeAmt,
                (netOut * mConfig.minNLendFeeR) / Constants.DECIMAL_BASE
            );
        }
        netOut -= feeAmt;
        if (netOut < minUnderlyingOut) {
            revert UnexpectedAmount(
                sender,
                minUnderlyingOut,
                netOut.toUint128()
            );
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

        underlying.transfer(sender, netOut);
        _config.apr = mConfig.apr;
        emit SellToken(
            sender,
            token,
            minUnderlyingOut,
            netOut.toUint128(),
            mConfig.apr
        );
    }

    function _lockFee(
        uint256 feeAmount,
        uint256 lockingPercentage,
        uint256 initialLtv
    ) internal {
        uint feeToLock = (feeAmount *
            lockingPercentage +
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

    function mintGt(
        uint128 xtAmt,
        bytes calldata callbackData
    ) external override isOpen nonReentrant returns (uint256 gtId) {
        return _mintGt(msg.sender, xtAmt, callbackData);
    }

    function _mintGt(
        address sender,
        uint128 xtAmt,
        bytes calldata callbackData
    ) internal returns (uint256 gtId) {
        xt.transferFrom(sender, address(this), xtAmt);

        // 1 xt -> 1 underlying raised
        // Debt 1 * initialLtv
        uint128 debt = ((xtAmt * _config.initialLtv) / Constants.DECIMAL_BASE)
            .toUint128();

        // Send debt to borrower
        underlying.transfer(sender, xtAmt);
        // Callback function
        bytes memory collateralData = IFlashLoanReceiver(sender)
            .executeOperation(sender, underlying, debt, callbackData);

        // Mint GT
        gtId = gt.mint(sender, debt, collateralData);

        emit MintGt(sender, gtId, debt, collateralData);
    }

    function lever(
        uint128 debt,
        bytes calldata collateralData
    ) external override isOpen nonReentrant returns (uint256 gtId) {
        return _lever(msg.sender, debt, collateralData);
    }

    function _lever(
        address sender,
        uint128 debt,
        bytes calldata collateralData
    ) internal returns (uint256 gtId) {
        // Mint GT
        gtId = gt.mint(sender, debt, collateralData);

        MarketConfig memory mConfig = _config;
        uint leverFee = (debt * mConfig.leverfeeRatio) / Constants.DECIMAL_BASE;
        ft.transfer(mConfig.treasurer, leverFee);
        ft.mint(sender, debt - leverFee);

        emit MintGt(sender, gtId, debt, collateralData);
    }

    function redeem(
        uint256[4] calldata amountArray
    ) external virtual override nonReentrant {
        _redeem(msg.sender, amountArray);
    }

    // function redeemByPermit(
    //     address sender,
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

    function _redeem(address sender, uint256[4] calldata amountArray) internal {
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
        }
        // k = (1 - initalLtv) * DECIMAL_BASE
        uint k = Constants.DECIMAL_BASE - mConfig.initialLtv;
        uint userPoint;
        // uint fee;
        {
            // Calculate lp tokens output
            uint lpFtAmt = amountArray[0];
            if (lpFtAmt > 0) {
                lpFt.transferFrom(sender, address(this), lpFtAmt);
                uint lpFtTotalSupply = lpFt.totalSupply();
                uint ftReserve = ft.balanceOf(address(this));
                userPoint += (lpFtAmt * ftReserve) / lpFtTotalSupply;
                lpFt.burn(lpFtAmt);
            }
            uint lpXtAmt = amountArray[1];
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
            uint ftAmt = amountArray[2];
            if (ftAmt > 0) {
                ft.transferFrom(sender, address(this), ftAmt);
                userPoint += ftAmt;
                ft.burn(ftAmt);
            }
            uint xtAmt = amountArray[3];
            if (xtAmt > 0) {
                xt.transferFrom(sender, address(this), xtAmt);
                userPoint += (xtAmt * k) / Constants.DECIMAL_BASE;
                xt.burn(xtAmt);
            }
        }

        // The ratio that user will get how many underlying and collateral when do redeem
        uint ratio = (userPoint * Constants.DECIMAL_BASE) / allPoints;
        bytes memory deliveryData = gt.delivery(ratio, sender);
        // Transfer underlying output
        uint underlyingAmt = (underlying.balanceOf(address(this)) * ratio) /
            Constants.DECIMAL_BASE;
        if (mConfig.redeemFeeRatio > 0) {
            underlyingAmt = _tranferFeeToTreasurer(
                mConfig.treasurer,
                underlyingAmt,
                mConfig.redeemFeeRatio
            );
        }
        underlying.transfer(sender, underlyingAmt);
        emit Redeem(
            sender,
            ratio.toUint128(),
            underlyingAmt.toUint128(),
            deliveryData
        );
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
        // Burn all ft tokens in gt
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

    function redeemFtAndXtToUnderlying(
        uint256 underlyingAmt
    ) external override nonReentrant isOpen {
        _redeemFtAndXtToUnderlying(msg.sender, underlyingAmt);
    }

    function _redeemFtAndXtToUnderlying(
        address sender,
        uint256 underlyingAmt
    ) internal {
        uint ftAmt = (underlyingAmt * _config.initialLtv) /
            Constants.DECIMAL_BASE;
        ft.transferFrom(sender, address(this), ftAmt);
        xt.transferFrom(sender, address(this), underlyingAmt);
        ft.burn(ftAmt);
        xt.burn(underlyingAmt);
        underlying.transfer(sender, underlyingAmt);

        emit RedeemFxAndXtToUnderlying(sender, underlyingAmt);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
