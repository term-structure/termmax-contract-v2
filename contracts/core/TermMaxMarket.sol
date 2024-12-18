// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITermMaxMarket, MarketConfig, IMintableERC20, IERC20} from "./ITermMaxMarket.sol";
import {IGearingToken} from "./tokens/IGearingToken.sol";
import {IFlashLoanReceiver} from "./IFlashLoanReceiver.sol";
import {TermMaxCurve, MathLib, TradeParams} from "./lib/TermMaxCurve.sol";
import {Constants} from "./lib/Constants.sol";
import {Ownable} from "./access/Ownable.sol";

/**
 * @title TermMax Market
 * @author Term Structure Labs
 */
contract TermMaxMarket is ITermMaxMarket, ReentrancyGuard, Ownable, Pausable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableERC20;
    using MathLib for *;

    MarketConfig private _config;
    address private collateral;
    IERC20 private underlying;
    IMintableERC20 private ft;
    IMintableERC20 private xt;
    IMintableERC20 private lpFt;
    IMintableERC20 private lpXt;
    IGearingToken private gt;
    /// @notice The time when the contract is suspended
    uint256 private pauseTime;

    // Track token reserves
    uint128 private ftReserve;
    uint128 private xtReserve;

    mapping(address => bool) public providerWhitelist;

    /// @notice Check if the market is tradable
    modifier isOpen() {
        _requireNotPaused();
        if (block.timestamp < _config.openTime || block.timestamp >= _config.maturity) {
            revert MarketIsNotOpen();
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
        __initializeOwner(admin);
        if (address(collateral_) == address(underlying_)) 
            revert CollateralCanNotEqualUnderlyinng();
        
        if (
            config_.openTime < block.timestamp ||
            config_.maturity < config_.openTime
        ) 
            revert InvalidTime(config_.openTime, config_.maturity);
        
        if (config_.lsf == 0 || config_.lsf > Constants.DECIMAL_BASE) 
            revert InvalidLsf(config_.lsf);
        
        underlying = underlying_;
        collateral = collateral_;
        config_.rewardIsDistributed = false;
        _config = config_;
        // Allow all providers
        providerWhitelist[address(0)] = true;
        ft = tokens_[0];
        xt = tokens_[1];
        lpFt = tokens_[2];
        lpXt = tokens_[3];
        gt = gt_;

        // Initialize reserves to 0
        ftReserve = 0;
        xtReserve = 0;

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
    function ftXtReserves() public view override returns (uint128, uint128) {
        return (ftReserve, xtReserve);
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
    function updateMarketConfig(
        MarketConfig calldata newConfig
    ) external override onlyOwner {
        MarketConfig memory mConfig = _config;
        if(newConfig.treasurer != mConfig.treasurer){
            mConfig.treasurer = newConfig.treasurer;
            gt.setTreasurer(newConfig.treasurer);
        }
        if (newConfig.lsf == 0 || newConfig.lsf > Constants.DECIMAL_BASE) {
            revert InvalidLsf(newConfig.lsf);
        }
        mConfig.lsf = newConfig.lsf;
        mConfig.minApr = newConfig.minApr;
        mConfig.lendFeeRatio = newConfig.lendFeeRatio;
        mConfig.minNLendFeeR = newConfig.minNLendFeeR;
        mConfig.borrowFeeRatio = newConfig.borrowFeeRatio;
        mConfig.minNBorrowFeeR = newConfig.minNBorrowFeeR;
        mConfig.redeemFeeRatio = newConfig.redeemFeeRatio;
        mConfig.issueFtFeeRatio = newConfig.issueFtFeeRatio;
        mConfig.lockingPercentage = newConfig.lockingPercentage;
        mConfig.protocolFeeRatio = newConfig.protocolFeeRatio;
        
        _config = mConfig;
        emit UpdateMarketConfig(mConfig);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function setProviderWhitelist(address provider, bool isWhiteList) external override onlyOwner {
        providerWhitelist[provider] = isWhiteList;
        emit UpdateProviderWhitelist(provider, isWhiteList);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function provideLiquidity(
        uint128 underlyingAmt
    )
        external
        nonReentrant
        isOpen
        returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt)
    {
        // If address(0) is not in the white list, and the caller is not in the white list, revert
        if (!providerWhitelist[address(0)] && !providerWhitelist[msg.sender])
         revert ProviderNotWhitelisted(msg.sender);
        (lpFtOutAmt, lpXtOutAmt) = _provideLiquidity(msg.sender, underlyingAmt);
    }

    function _provideLiquidity(
        address caller,
        uint256 underlyingAmt
    ) internal returns (uint128 lpFtOutAmt, uint128 lpXtOutAmt) {
        
        uint lpFtTotalSupply = lpFt.totalSupply();
        uint lpXtTotalSupply = lpXt.totalSupply();
        uint oldFtReserve = ftReserve;
        uint oldXtReserve = xtReserve;
        (uint128 ftMintedAmt, uint128 xtMintedAmt) = _addLiquidity(
            caller,
            underlyingAmt,
            _config.initialLtv
        );
        lpFtOutAmt = TermMaxCurve.calculateLpOut(ftMintedAmt, oldFtReserve, lpFtTotalSupply).toUint128();
        lpXtOutAmt = TermMaxCurve.calculateLpOut(xtMintedAmt, oldXtReserve, lpXtTotalSupply).toUint128();
        if(lpFtOutAmt == 0 || lpXtOutAmt == 0) revert LpOutputAmtIsZero(underlyingAmt);
        
        MarketConfig memory mConfig = _config;
        // uint totalFtRewards = lpFt.balanceOf(address(this));
        // uint totalXtRewards = lpXt.balanceOf(address(this));
        
        // lpFt.mint(address(this), lpFtOutAmt);
        // lpXt.mint(address(this), lpXtOutAmt);
        
        // lpFtOutAmt = TermMaxCurve.calculateLpWithoutReward(
        //     block.timestamp, 
        //     mConfig.openTime,
        //     mConfig.maturity, 
        //     lpFtTotalSupply, 
        //     lpFtOutAmt, 
        //     totalFtRewards
        // ).toUint128();
        
        // lpXtOutAmt = TermMaxCurve.calculateLpWithoutReward(
        //     block.timestamp,
        //     mConfig.openTime,
        //     mConfig.maturity,
        //     lpXtTotalSupply,
        //     lpXtOutAmt,
        //     totalXtRewards
        // ).toUint128();
        // lpFt.safeTransfer(caller, lpFtOutAmt);
        // lpXt.safeTransfer(caller, lpXtOutAmt);
        lpFt.mint(caller, lpFtOutAmt);
        lpXt.mint(caller, lpXtOutAmt);
        emit ProvideLiquidity(
            caller,
            underlyingAmt,
            lpFtOutAmt,
            lpXtOutAmt,
            ftReserve,
            xtReserve
        );
    }

    function _addLiquidity(
        address caller,
        uint256 underlyingAmt,
        uint256 ltv
    ) internal returns (uint128 ftMintedAmt, uint128 xtMintedAmt) {
        underlying.safeTransferFrom(caller, address(this), underlyingAmt);

        ftMintedAmt = ((underlyingAmt * ltv) / Constants.DECIMAL_BASE)
            .toUint128();
        xtMintedAmt = underlyingAmt.toUint128();
        // Mint tokens to this
        ft.mint(address(this), ftMintedAmt);
        xt.mint(address(this), xtMintedAmt);
        ftReserve += ftMintedAmt;
        xtReserve += xtMintedAmt;
    }

    function _removeLiquidity(
        address to,
        uint256 underlyingAmt,
        uint256 ltv
    ) internal returns (uint128 ftBurnedAmt, uint128 xtBurnedAmt) {
        underlying.safeTransfer(to, underlyingAmt);
        // Carry calculation to avoid the situation that ft amount is 0
        ftBurnedAmt = ((underlyingAmt * ltv + Constants.DECIMAL_BASE - 1) / Constants.DECIMAL_BASE)
            .toUint128();
        xtBurnedAmt = underlyingAmt.toUint128();
        // Burn tokens to this
        ft.burn(ftBurnedAmt);
        xt.burn(xtBurnedAmt);
        ftReserve -= ftBurnedAmt;
        xtReserve -= xtBurnedAmt;
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
    function withdrawLiquidity(
        uint128 lpFtAmt,
        uint128 lpXtAmt
    )
        external
        override
        nonReentrant
        isOpen
        returns (uint128 ftOutAmt, uint128 xtOutAmt)
    {
        (ftOutAmt, xtOutAmt) = _withdrawLiquidity(msg.sender, lpFtAmt, lpXtAmt);
    }

    function _withdrawLiquidity(
        address caller,
        uint256 lpFtAmt,
        uint256 lpXtAmt
    ) internal returns (uint128 ftOutAmt, uint128 xtOutAmt) {
        MarketConfig memory mConfig = _config;
        // calculate out put amount
        if (lpFtAmt > 0) {
            uint lpFtTotalSupply = lpFt.totalSupply();
            // uint256 lpFtAmtWithReward = lpFtAmt + TermMaxCurve.calculateLpReward(
            //     block.timestamp,
            //     mConfig.openTime,
            //     mConfig.maturity,
            //     lpFtTotalSupply,
            //     lpFtAmt,
            //     lpFt.balanceOf(address(this))
            // );
            // ftOutAmt = ((lpFtAmtWithReward * ftReserve) / lpFtTotalSupply).toUint128();
            // lpFt.safeTransferFrom(caller, address(this), lpFtAmt);
            // lpFt.burn(lpFtAmtWithReward);
            ftOutAmt = ((lpFtAmt * ftReserve) / lpFtTotalSupply).toUint128();
            lpFt.safeTransferFrom(caller, address(this), lpFtAmt);
            lpFt.burn(lpFtAmt);
        }
        if (lpXtAmt > 0) {
            uint lpXtTotalSupply = lpXt.totalSupply();
            // uint256 lpXtAmtWithReward = lpXtAmt + TermMaxCurve.calculateLpReward(
            //     block.timestamp,
            //     mConfig.openTime,
            //     mConfig.maturity,
            //     lpXtTotalSupply,
            //     lpXtAmt,
            //     lpXt.balanceOf(address(this))
            // );
            // xtOutAmt = ((lpXtAmtWithReward * xtReserve) / lpXtTotalSupply).toUint128();
            // lpXt.safeTransferFrom(caller, address(this), lpXtAmt);
            // lpXt.burn(lpXtAmtWithReward);
            xtOutAmt = ((lpXtAmt * xtReserve) / lpXtTotalSupply).toUint128();
            lpXt.safeTransferFrom(caller, address(this), lpXtAmt);
            lpXt.burn(lpXtAmt);
        }
        if (xtOutAmt >= xtReserve || ftOutAmt >= ftReserve) {
            revert TermMaxCurve.LiquidityIsZeroAfterTransaction();
        }
        // Ref docs: https://docs.ts.finance/termmax/technical-details/amm-model/pool-operations/liquidity-operations-l#lo2-withdraw-liquidity
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
            ft.safeTransfer(caller, ftOutAmt);
            ftReserve -= ftOutAmt;
        }
        if (xtOutAmt > 0) {
            xt.safeTransfer(caller, xtOutAmt);
            xtReserve -= xtOutAmt;
        }
        _updateApr(mConfig);
        emit WithdrawLiquidity(
            caller,
            lpFtAmt.toUint128(),
            lpXtAmt.toUint128(),
            ftOutAmt,
            xtOutAmt,
            mConfig.apr,
            ftReserve,
            xtReserve
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyFt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut,
        uint32 lsf
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, ft, underlyingAmtIn, minTokenOut, lsf);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function buyXt(
        uint128 underlyingAmtIn,
        uint128 minTokenOut,
        uint32 lsf
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, xt, underlyingAmtIn, minTokenOut, lsf);
    }

    function _buyToken(
        address caller,
        IMintableERC20 token,
        uint128 underlyingAmtIn,
        uint128 minTokenOut,
        uint32 lsf
    ) internal returns (uint256 netOut) {
        // Get old reserves
        MarketConfig memory mConfig = _config;
        if(lsf != mConfig.lsf){
            revert LsfChanged();
        }
        TradeParams memory tradeParams = TradeParams(
            underlyingAmtIn,
            ftReserve,
            xtReserve,
            _daysToMaturity(mConfig.maturity)
        );

        uint feeAmt;
        uint finalTokenReserve;
        if (token == ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.buyFt(
                tradeParams,
                mConfig
            );
            // calculate fee
            feeAmt = TermMaxCurve.calculateTxFee(
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

            (finalTokenReserve, , mConfig.apr) = TermMaxCurve.buyNegFt(
                TradeParams(
                    feeAmt,
                    newFtReserve,
                    newXtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.buyXt(
                tradeParams,
                mConfig
            );
            // calculate fee
            feeAmt = TermMaxCurve.calculateTxFee(
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
            (, finalTokenReserve, mConfig.apr) = TermMaxCurve.buyNegXt(
                TradeParams(
                    feeAmt,
                    newFtReserve,
                    newXtReserve,
                    tradeParams.daysToMaturity
                ),
                mConfig
            );
        }
        {
            // Fee to protocol
            uint feeToProtocol = _tranferFeeToTreasurerBuyToken(
                mConfig.treasurer,
                feeAmt,
                mConfig.protocolFeeRatio,
                caller
            );
            // add new lituidity(exclude fee to protocol)
            _addLiquidity(
                caller,
                underlyingAmtIn - feeToProtocol,
                mConfig.initialLtv
            );
            feeAmt -= feeToProtocol;

            if (token == ft) {
                netOut =
                    ftReserve -
                    finalTokenReserve -
                    (feeAmt * mConfig.initialLtv) /
                    Constants.DECIMAL_BASE;
                ftReserve -= netOut.toUint128();
            } else {
                netOut =
                    xtReserve -
                    finalTokenReserve -
                    feeAmt;
                xtReserve -= netOut.toUint128();
            }
            if (netOut < minTokenOut) {
                revert UnexpectedAmount(minTokenOut, netOut.toUint128());
            }
            token.safeTransfer(caller, netOut);
            // // _lock_fee
            // _lockFee(feeAmt, mConfig.lockingPercentage, mConfig.initialLtv);
            feeAmt += feeToProtocol;
        }
        _updateApr(mConfig);
        emit BuyToken(
            caller,
            token,
            underlyingAmtIn,
            minTokenOut,
            netOut.toUint128(),
            feeAmt.toUint128(),
            mConfig.apr,
            ftReserve,
            xtReserve
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellFt(
        uint128 ftAmtIn,
        uint128 minUnderlyingOut,
        uint32 lsf
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _sellToken(msg.sender, ft, ftAmtIn, minUnderlyingOut, lsf);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function sellXt(
        uint128 xtAmtIn,
        uint128 minUnderlyingOut,
        uint32 lsf
    ) external override nonReentrant isOpen returns (uint256 netOut) {
        netOut = _sellToken(msg.sender, xt, xtAmtIn, minUnderlyingOut, lsf);
    }

    function _sellToken(
        address caller,
        IMintableERC20 token,
        uint128 tokenAmtIn,
        uint128 minUnderlyingOut,
        uint32 lsf
    ) internal returns (uint256 netOut) {
        MarketConfig memory mConfig = _config;
        if(lsf != mConfig.lsf){
            revert LsfChanged();
        }
        token.safeTransferFrom(caller, address(this), tokenAmtIn);
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
            feeAmt = TermMaxCurve.calculateTxFee(
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
            ftReserve += tokenAmtIn;
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, mConfig.apr) = TermMaxCurve.sellXt(
                tradeParams,
                mConfig
            );
            netOut = tokenAmtIn + xtReserve - newXtReserve;
            // calculate fee
            feeAmt = TermMaxCurve.calculateTxFee(
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
            xtReserve += tokenAmtIn;
        }
        netOut -= feeAmt;
        if (netOut < minUnderlyingOut) {
            revert UnexpectedAmount(minUnderlyingOut, netOut.toUint128());
        }
        // Fee to prootocol
        _tranferFeeToTreasurer(
            mConfig.treasurer,
            feeAmt,
            mConfig.protocolFeeRatio,
            mConfig.initialLtv
        );

        _removeLiquidity(caller, netOut, mConfig.initialLtv);
        // _lockFee(
        //     feeAmt - feeToProtocol,
        //     mConfig.lockingPercentage,
        //     mConfig.initialLtv
        // );

        _updateApr(mConfig);
        emit SellToken(
            caller,
            token,
            tokenAmtIn,
            minUnderlyingOut,
            netOut.toUint128(),
            feeAmt.toUint128(),
            mConfig.apr,
            ftReserve,
            xtReserve
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
        uint ftAmt = (underlyingAmt * _config.initialLtv + Constants.DECIMAL_BASE - 1) /
            Constants.DECIMAL_BASE;
        ft.safeTransferFrom(caller, address(this), ftAmt);
        xt.safeTransferFrom(caller, address(this), underlyingAmt);
        ftReserve += ftAmt.toUint128();
        xtReserve += underlyingAmt.toUint128();
        _removeLiquidity(caller, underlyingAmt, _config.initialLtv);

        emit RemoveLiquidity(
            caller,
            underlyingAmt,
            ftReserve,
            xtReserve
        );
    }

    // /// @notice Lock up a portion of the transaction fee and release it slowly in the later stage
    // function _lockFee(
    //     uint256 feeAmount,
    //     uint256 lockingPercentage,
    //     uint256 initialLtv
    // ) internal {
    //     uint feeToLock = (feeAmount *
    //         lockingPercentage +
    //         Constants.DECIMAL_BASE -
    //         1) / Constants.DECIMAL_BASE;
    //     uint ftAmount = (feeToLock * initialLtv) / Constants.DECIMAL_BASE;

    //     uint lpFtAmt = TermMaxCurve.calculateLpOut(
    //         ftAmount,
    //         ftReserve - ftAmount,
    //         lpFt.totalSupply()
    //     );
    //     lpFt.mint(address(this), lpFtAmt);

    //     uint lpXtAmt = TermMaxCurve.calculateLpOut(
    //         feeToLock,
    //         xtReserve - feeToLock,
    //         lpXt.totalSupply()
    //     );
    //     lpXt.mint(address(this), lpXtAmt);
    // }

    /**
     * @inheritdoc ITermMaxMarket
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
        // Debt 1 * initialLtv round up
        uint128 debt = ((xtAmt *
            _config.initialLtv +
            Constants.DECIMAL_BASE -
            1) / Constants.DECIMAL_BASE).toUint128();

        // Send debt to borrower
        underlying.safeTransfer(loanReceiver, xtAmt);
        // Callback function
        bytes memory collateralData = IFlashLoanReceiver(loanReceiver)
            .executeOperation(gtReceiver, underlying, xtAmt, callbackData);

        // Mint GT
        gtId = gt.mint(loanReceiver, gtReceiver, debt, collateralData);

        xt.burn(xtAmt);
        xtReserve -= xtAmt;
        emit MintGt(loanReceiver, gtReceiver, gtId, debt, collateralData);
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
        nonReentrant
        isOpen
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
        ftReserve += issueFee;
        ftOutAmt = debt - issueFee;
        ft.mint(caller, ftOutAmt);
        ftReserve += ftOutAmt;

        emit IssueFt(
            caller,
            gtId,
            debt,
            ftOutAmt,
            issueFee,
            collateralData
        );
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function redeem(
        uint256[4] calldata amountArray
    ) external virtual override nonReentrant {
        _redeem(msg.sender, amountArray);
    }

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
        uint underlyingAmt;
        uint totalXtAsUnderlying;

        {
            uint xtAmt = amountArray[1];

            uint lpXtAmt = amountArray[3];
            if (lpXtAmt > 0) {
                lpXt.safeTransferFrom(caller, address(this), lpXtAmt);
                uint lpXtTotalSupply = lpXt.totalSupply();

                xtAmt += (lpXtAmt * xt.balanceOf(address(this))) / lpXtTotalSupply;
                lpXt.burn(lpXtAmt);
            }
            if (amountArray[1] > 0) {
                xt.safeTransferFrom(caller, address(this), amountArray[1]);
            }
            // k = (1 - initalLtv) * DECIMAL_BASE
            uint k = Constants.DECIMAL_BASE - mConfig.initialLtv;
            totalXtAsUnderlying =
                (xt.totalSupply() * k) /
                Constants.DECIMAL_BASE;

            if (xtAmt > 0) {
                xt.burn(xtAmt);
                underlyingAmt = (xtAmt * k) / Constants.DECIMAL_BASE;
            }
        }
        // The proportion that user will get how many underlying and collateral should be deliveried
        uint proportion;
        {
            uint ftAmt = amountArray[0];

            // Calculate lp tokens output
            uint lpFtAmt = amountArray[2];
            if (lpFtAmt > 0) {
                lpFt.safeTransferFrom(caller, address(this), lpFtAmt);
                uint lpFtTotalSupply = lpFt.totalSupply();
                ftAmt += (lpFtAmt * ft.balanceOf(address(this))) / lpFtTotalSupply;
                lpFt.burn(lpFtAmt);
            }
            proportion = (ftAmt * Constants.DECIMAL_BASE_SQ) / ft.totalSupply();

            if (amountArray[0] > 0) {
                ft.safeTransferFrom(caller, address(this), amountArray[0]);
            }
            if (ftAmt > 0) {
                ft.burn(ftAmt);
            }
        }

        bytes memory deliveryData = gt.delivery(proportion, caller);
        // Transfer underlying output
        underlyingAmt +=
            ((underlying.balanceOf(address(this)) - totalXtAsUnderlying) *
                proportion) /
            Constants.DECIMAL_BASE_SQ;
        uint feeAmt;
        if (mConfig.redeemFeeRatio > 0) {
            feeAmt =
                (underlyingAmt * mConfig.redeemFeeRatio) /
                Constants.DECIMAL_BASE;
            underlying.safeTransfer(mConfig.treasurer, feeAmt);
            underlyingAmt -= feeAmt;
        }
        underlying.safeTransfer(caller, underlyingAmt);
        emit Redeem(
            caller,
            proportion.toUint128(),
            underlyingAmt.toUint128(),
            feeAmt.toUint128(),
            deliveryData
        );
    }

    /// @notice Release all locked rewards
    function _distributeAllReward() internal {
        _burnLpInTheMarket();
        // Burn all ft in gt
        uint amount = ft.balanceOf(address(gt));
        ft.safeTransferFrom(address(gt), address(this), amount);
        ft.burn(amount);
    }

    function _burnLpInTheMarket() internal {
        uint lpFtBalance = lpFt.balanceOf(address(this));
        uint lpXtBalance = lpXt.balanceOf(address(this));
        lpFt.burn(lpFtBalance);
        lpXt.burn(lpXtBalance);
    }

    function _tranferFeeToTreasurerBuyToken(
        address treasurer,
        uint256 totalFee,
        uint32 protocolFeeRatio,
        address caller
    ) internal returns (uint256 feeToProtocol) {
        feeToProtocol = (totalFee * protocolFeeRatio) / Constants.DECIMAL_BASE;
        underlying.safeTransferFrom(caller, treasurer, feeToProtocol);
    }

    function _tranferFeeToTreasurer(
        address treasurer,
        uint256 totalFee,
        uint32 protocolFeeRatio,
        uint256 ltv
    ) internal returns (uint256 feeToProtocol) {
        feeToProtocol = (totalFee * protocolFeeRatio) / Constants.DECIMAL_BASE;
        _removeLiquidity(treasurer, feeToProtocol, ltv);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function pause() external override onlyOwner {
        _pause();
        pauseTime = block.timestamp;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function unpause() external override onlyOwner {
        if (_getEvacuateStatus()) {
            revert EvacuationIsActived();
        }
        _unpause();
        pauseTime = 0;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function updateGtConfig(bytes memory configData) external override onlyOwner{
        gt.updateConfig(configData);
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function evacuate(
        uint128 lpFtAmt,
        uint128 lpXtAmt
    ) external override nonReentrant {
        if (!_getEvacuateStatus()) {
            revert EvacuationIsNotActived();
        }
        _evacuate(msg.sender, lpFtAmt, lpXtAmt);
    }

    function _evacuate(
        address caller,
        uint128 lpFtAmt,
        uint128 lpXtAmt
    ) internal {
        _burnLpInTheMarket();
        MarketConfig memory mConfig = _config;

        // calculate out put amount
        uint ftAmt = (lpFtAmt * ft.balanceOf(address(this))) / lpFt.totalSupply();
        // will burn in the next time
        lpFt.safeTransferFrom(caller, address(this), lpFtAmt);

        uint xtAmt = (lpXtAmt * xt.balanceOf(address(this))) / lpXt.totalSupply();
        // will burn in the next time
        lpXt.safeTransferFrom(caller, address(this), lpXtAmt);

        uint sameProportionFt = (xtAmt * mConfig.initialLtv + Constants.DECIMAL_BASE - 1) /
            Constants.DECIMAL_BASE;

        // Judge the max redeemed underlying
        // Case 1: ftAmt >  xtAmt * ltv  redeem xtAmt, safeTransfer excess ft
        // Case 2: ftAmt <= xtAmt * ltv  redeem ftAmt/ltv, safeTransfer excess xt
        if (ftAmt > sameProportionFt) {
            ft.safeTransfer(caller, ftAmt - sameProportionFt);
            ft.burn(sameProportionFt);
            xt.burn(xtAmt);
            underlying.safeTransfer(caller, xtAmt);
            emit Evacuate(
                caller,
                lpFtAmt,
                lpXtAmt,
                uint128(ftAmt - sameProportionFt),
                0,
                xtAmt
            );
        } else {
            uint xtToBurn = (ftAmt * Constants.DECIMAL_BASE) / mConfig.initialLtv;
            xt.safeTransfer(caller, xtAmt - xtToBurn);
            ft.burn(ftAmt);
            xt.burn(xtToBurn);
            underlying.safeTransfer(caller, xtToBurn);
            emit Evacuate(caller, lpFtAmt, lpXtAmt, 0, uint128(xtAmt - xtToBurn), xtToBurn);
        }
    }

    function _getEvacuateStatus() internal view returns (bool) {
        return
            paused() &&
            block.timestamp - pauseTime >
            Constants.WAITING_TIME_EVACUATION_ACTIVE &&
            block.timestamp < _config.maturity;
    }

    function _updateApr(MarketConfig memory mConfig) private{
        if(mConfig.apr < mConfig.minApr)
            revert AprLessThanMinApr(mConfig.apr, mConfig.minApr); 
        _config.apr = mConfig.apr;
    }

    /**
     * @inheritdoc ITermMaxMarket
     */
    function withdrawExcessFtXt(address to, uint128 ftAmt, uint128 xtAmt) external onlyOwner isOpen { 
        if(uint256(ftAmt) + ftReserve > ft.balanceOf(address(this)) || uint256(xtAmt) + xtReserve > xt.balanceOf(address(this)))
            revert NotEnoughFtOrXtToWithdraw();
        if(ftAmt > 0)
            ft.safeTransfer(to, ftAmt);
        if(xtAmt > 0)
            xt.safeTransfer(to, xtAmt);
        emit WithdrawExcessFtXt(to, ftAmt, xtAmt);
    }
}
