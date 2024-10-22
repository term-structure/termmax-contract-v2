// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITermMaxMarket} from "../interfaces/ITermMaxMarket.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";
import {IFlashLoanReceiver} from "../interfaces/IFlashLoanReceiver.sol";
import {TermMaxCurve} from "./lib/TermMaxCurve.sol";
import {TermMaxStorage} from "./storage/TermMaxStorage.sol";

abstract contract AbstractTermMaxMarket is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ITermMaxMarket,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    string constant PREFIX_FT = "FT:";
    string constant PREFIX_XT = "XT:";
    string constant PREFIX_LP_FT = "LpFT:";
    string constant PREFIX_LP_XT = "LpXT:";

    modifier isOpen() {
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        if (block.timestamp < config.openTime) {
            revert MarketIsNotOpen();
        }
        if (block.timestamp >= config.maturity) {
            revert MarketWasClosed();
        }
        _;
    }

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
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
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        uint ftReserve = tokens.ft.balanceOf(address(this));
        uint lpFtTotalSupply = tokens.lpFt.totalSupply();

        uint xtReserve = tokens.xt.balanceOf(address(this));
        uint lpXtTotalSupply = tokens.lpXt.totalSupply();
        (uint128 ftMintedAmt, uint128 xtMintedAmt) = _addLiquidity(
            sender,
            cashAmt,
            config.initialLtv,
            tokens
        );

        lpFtOutAmt = TermMaxCurve
            ._calculateLpOut(ftMintedAmt, ftReserve, lpFtTotalSupply)
            .toUint128();

        lpXtOutAmt = TermMaxCurve
            ._calculateLpOut(xtMintedAmt, xtReserve, lpXtTotalSupply)
            .toUint128();
        tokens.lpXt.mint(sender, lpXtOutAmt);
        tokens.lpFt.mint(sender, lpFtOutAmt);

        emit ProvideLiquidity(sender, cashAmt, lpFtOutAmt, lpXtOutAmt);
    }

    function _addLiquidity(
        address sender,
        uint256 cashAmt,
        uint256 ltv,
        TermMaxStorage.MarketTokens memory tokens
    ) internal returns (uint128 ftMintedAmt, uint128 xtMintedAmt) {
        tokens.cash.transferFrom(sender, address(this), cashAmt);

        ftMintedAmt = cashAmt.mulDiv(ltv, TermMaxCurve.DECIMAL_BASE).toUint128();
        xtMintedAmt = cashAmt.toUint128();
        // Mint tokens to this
        tokens.ft.mint(address(this), ftMintedAmt);
        tokens.xt.mint(address(this), xtMintedAmt);

        emit AddLiquidity(sender, cashAmt, ftMintedAmt, xtMintedAmt);
    }

    function _daysTomaturity(
        uint maturity
    ) internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (maturity - block.timestamp) /
            TermMaxCurve.SECONDS_IN_DAY;
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
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        // get token reserves
        uint ftReserve = tokens.ft.balanceOf(address(this));
        uint xtReserve = tokens.xt.balanceOf(address(this));
        uint lpFtTotalSupply;
        uint lpXtTotalSupply;
        // calculate reward
        if (lpFtAmt > 0) {
            tokens.lpFt.transferFrom(sender, address(this), lpFtAmt);

            lpFtTotalSupply = tokens.lpFt.totalSupply();
            uint reward = TermMaxCurve.calculateLpReward(
                block.timestamp,
                config.openTime,
                config.maturity,
                lpFtTotalSupply,
                lpFtAmt,
                tokens.lpFt.balanceOf(address(this))
            );
            lpFtAmt += reward;
            tokens.lpFt.burn(lpFtAmt);
            ftOutAmt = lpFtAmt.mulDiv(ftReserve, lpFtTotalSupply).toUint128();
        }
        if (lpXtAmt > 0) {
            tokens.lpXt.transferFrom(sender, address(this), lpXtAmt);

            lpXtTotalSupply = tokens.lpXt.totalSupply();
            uint reward = TermMaxCurve.calculateLpReward(
                block.timestamp,
                config.openTime,
                config.maturity,
                lpXtTotalSupply,
                lpXtAmt,
                tokens.lpXt.balanceOf(address(this))
            );
            lpXtAmt += reward;
            tokens.lpXt.burn(lpXtAmt);
            xtOutAmt = lpXtAmt.mulDiv(xtReserve, lpXtTotalSupply).toUint128();
        }
        uint sameProportionFt = uint(xtOutAmt).mulDiv(
            config.initialLtv,
            TermMaxCurve.DECIMAL_BASE
        );
        if (sameProportionFt > ftOutAmt) {
            uint xtExcess = (sameProportionFt - ftOutAmt).mulDiv(
                TermMaxCurve.DECIMAL_BASE,
                config.initialLtv
            );
            TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve
                .TradeParams(
                    xtExcess,
                    ftReserve,
                    xtReserve,
                    _daysTomaturity(config.maturity)
                );
            (, , config.apy) = TermMaxCurve._sellNegXt(tradeParams, config);
        } else if (sameProportionFt < ftOutAmt) {
            uint ypExcess = ftOutAmt - sameProportionFt;
            TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve
                .TradeParams(
                    ypExcess,
                    ftReserve,
                    xtReserve,
                    _daysTomaturity(config.maturity)
                );
            (, , config.apy) = TermMaxCurve._sellNegFt(tradeParams, config);
        }
        TermMaxStorage._getConfig().apy = config.apy;
        if (ftOutAmt > 0) {
            tokens.xt.transfer(sender, ftOutAmt);
        }
        if (xtOutAmt > 0) {
            tokens.ft.transfer(sender, xtOutAmt);
        }
        emit WithdrawLP(
            sender,
            lpFtAmt.toUint128(),
            lpXtAmt.toUint128(),
            ftOutAmt,
            xtOutAmt,
            config.apy
        );
    }

    function buyFt(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        netOut = _buyToken(
            msg.sender,
            tokens.ft,
            cashAmtIn,
            minTokenOut,
            tokens
        );
    }

    function buyXt(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        netOut = _buyToken(
            msg.sender,
            tokens.xt,
            cashAmtIn,
            minTokenOut,
            tokens
        );
    }

    function _buyToken(
        address sender,
        IMintableERC20 token,
        uint128 cashAmtIn,
        uint128 minTokenOut,
        TermMaxStorage.MarketTokens memory tokens
    ) internal returns (uint256 netOut) {
        // Get old reserves
        uint ftReserve = tokens.ft.balanceOf(address(this));
        uint xtReserve = tokens.xt.balanceOf(address(this));

        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve.TradeParams(
            cashAmtIn,
            ftReserve,
            xtReserve,
            _daysTomaturity(config.maturity)
        );

        uint feeAmt;
        // add new lituidity
        _addLiquidity(sender, cashAmtIn, config.initialLtv, tokens);
        if (token == tokens.ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, config.apy) = TermMaxCurve.buyFt(
                tradeParams,
                config
            );
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                config.lendFeeRatio,
                config.initialLtv
            );
            //TODO protocol reward
            uint finalFtReserve;
            (finalFtReserve, , config.apy) = TermMaxCurve.buyNegFt(
                TermMaxCurve.TradeParams(
                    feeAmt,
                    ftReserve,
                    xtReserve,
                    tradeParams.daysToMaturity
                ),
                config
            );

            uint ypCurrentReserve = tokens.ft.balanceOf(address(this));
            netOut = ypCurrentReserve - finalFtReserve;
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, config.apy) = TermMaxCurve.buyXt(
                tradeParams,
                config
            );
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                config.borrowFeeRatio,
                config.initialLtv
            );
            //TODO protocol reward
            uint finalXtReserve;
            (finalXtReserve, , config.apy) = TermMaxCurve.buyNegXt(
                TermMaxCurve.TradeParams(
                    feeAmt,
                    ftReserve,
                    xtReserve,
                    tradeParams.daysToMaturity
                ),
                config
            );
            uint yaCurrentReserve = tokens.xt.balanceOf(address(this));
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
        _lockFee(feeAmt, config, tokens);
        TermMaxStorage._getConfig().apy = config.apy;
        emit BuyToken(
            sender,
            token,
            minTokenOut,
            netOut.toUint128(),
            config.apy
        );
    }

    function _sellToken(
        address sender,
        IMintableERC20 token,
        uint128 tokenAmtIn,
        uint128 minCashOut
    ) internal returns (uint256 netOut) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        token.transferFrom(sender, address(this), tokenAmtIn);
        // Get old reserves
        uint ftReserve = tokens.ft.balanceOf(address(this));
        uint xtReserve = tokens.xt.balanceOf(address(this));
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        TermMaxCurve.TradeParams memory tradeParams = TermMaxCurve.TradeParams(
            tokenAmtIn,
            ftReserve,
            xtReserve,
            _daysTomaturity(config.maturity)
        );
        uint feeAmt;
        if (token == tokens.ft) {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, config.apy) = TermMaxCurve.sellFt(
                tradeParams,
                config
            );
            netOut = xtReserve - newFtReserve;
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                config.borrowFeeRatio,
                config.initialLtv
            );
        } else {
            uint newFtReserve;
            uint newXtReserve;
            (newFtReserve, newXtReserve, config.apy) = TermMaxCurve.sellXt(
                tradeParams,
                config
            );
            netOut = tokenAmtIn + xtReserve - newFtReserve;
            // calculate fee
            feeAmt = TermMaxCurve.calculateFee(
                ftReserve,
                xtReserve,
                newFtReserve,
                newXtReserve,
                config.lendFeeRatio,
                config.initialLtv
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
        //TODO protcol reward
        _lockFee(feeAmt, config, tokens);
        token.burn(tokenAmtIn);
        tokens.cash.transfer(sender, netOut);
        TermMaxStorage._getConfig().apy = config.apy;
        emit SellToken(
            sender,
            token,
            minCashOut,
            netOut.toUint128(),
            config.apy
        );
    }

    function _lockFee(
        uint256 feeAmount,
        TermMaxStorage.MarketConfig memory config,
        TermMaxStorage.MarketTokens memory tokens
    ) internal {
        uint feeToLock = (feeAmount + 1) / 2;
        uint ypAmount = feeToLock.mulDiv(
            config.initialLtv,
            TermMaxCurve.DECIMAL_BASE
        );

        uint lpFtAmt = TermMaxCurve._calculateLpOut(
            ypAmount,
            tokens.ft.balanceOf(address(this)) - ypAmount,
            tokens.lpFt.totalSupply()
        );
        tokens.lpFt.mint(address(this), lpFtAmt);

        uint lpXtAmt = TermMaxCurve._calculateLpOut(
            feeToLock,
            tokens.xt.balanceOf(address(this)) - feeToLock,
            tokens.lpXt.totalSupply()
        );
        tokens.lpXt.mint(address(this), lpXtAmt);
    }

    function mintGNft(
        uint128 yaAmt,
        bytes memory collateralData,
        bytes calldata callbackData
    ) external override isOpen nonReentrant returns (uint256 nftId) {
        return _mintGNft(msg.sender, collateralData, yaAmt, callbackData);
    }

    function _mintGNft(
        address sender,
        bytes memory collateralData,
        uint128 yaAmt,
        bytes calldata callbackData
    ) internal returns (uint256 nftId) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        tokens.xt.transferFrom(sender, address(this), yaAmt);

        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        if (yaAmt < config.minLeveragedXt) {
            revert XTAmountTooLittle(sender, yaAmt, collateralData);
        }
        uint debt = (yaAmt * config.initialLtv) / TermMaxCurve.DECIMAL_BASE;
        uint128 health = _calcHealth(debt, tokens.cash, collateralData)
            .toUint128();
        if (health >= config.maxLtv) {
            revert GNftIsNotHealthy(
                sender,
                debt.toUint128(),
                health,
                collateralData
            );
        }
        // Send debt to borrower
        tokens.cash.transfer(sender, debt);
        // Callback function
        if (
            !IFlashLoanReceiver(sender).executeOperation(
                sender,
                tokens.cash,
                debt,
                callbackData
            )
        ) {
            revert MintGNFTFailedCallback(
                sender,
                yaAmt,
                debt.toUint128(),
                callbackData
            );
        }
        // Transfer collateral from sender to here
        _transferCollateralFrom(
            sender,
            address(this),
            tokens.collateralToken,
            collateralData
        );
        // Mint G-NFT
        nftId = tokens.gNft.mint(sender, debt, collateralData);
        emit MintGNft(sender, nftId, debt.toUint128(), collateralData);
    }

    function _transferCollateralFrom(
        address from,
        address to,
        address collateral,
        bytes memory collateralData
    ) internal virtual;

    function _transferCollateral(
        address to,
        address collateral,
        bytes memory collateralData
    ) internal virtual;

    function _calcHealth(
        uint256 debtAmt,
        IERC20 cash,
        bytes memory collateralData
    ) internal view virtual returns (uint256 health) {
        uint collateralValue = _sizeCollateralValue(collateralData, cash);
        health = debtAmt.mulDiv(TermMaxCurve.DECIMAL_BASE, collateralValue);
    }

    function _sizeCollateralValue(
        bytes memory collateralData,
        IERC20 cash
    ) internal view virtual returns (uint256);

    // function _calcHealth2(
    //     uint256 debtAmt,
    //     bytes calldata collateralData,
    //     TermMaxStorage.MarketConfig memory config,
    //     TermMaxStorage.MarketTokens memory tokens
    // ) internal view returns (uint256 health) {
    //     // Get the price collateralToken/cash
    //     (, int collateralPrice, , , ) = config
    //         .collateralOracle
    //         .latestRoundData();
    //     uint decimals = IERC20Metadata(address(tokens.cash)).decimals();
    //     uint collateralValue = collateralAmt.mulDiv(
    //         collateralPrice.toUint256(),
    //         10 ** decimals
    //     );
    //     health = debtAmt.mulDiv(TermMaxCurve.DECIMAL_BASE, collateralValue);
    // }

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
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        if (debtAmt < config.minLeveredFt) {
            revert XTAmountTooLittle(sender, debtAmt, collateralData);
        }
        uint128 health = _calcHealth(debtAmt, tokens.cash, collateralData)
            .toUint128();
        if (health >= config.maxLtv) {
            revert GNftIsNotHealthy(sender, debtAmt, health, collateralData);
        }
        _transferCollateralFrom(
            sender,
            address(this),
            tokens.collateralToken,
            collateralData
        );

        tokens.ft.mint(sender, debtAmt);
        // Mint G-NFT
        nftId = tokens.gNft.mint(sender, debtAmt, collateralData);
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
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        (address owner, uint128 debtAmt, bytes memory collateralData) = tokens
            .gNft
            .loanInfo(nftId);
        if (sender != owner) {
            revert SenderIsNotTheGNftOwner(sender, nftId);
        }
        tokens.cash.transferFrom(sender, address(this), repayAmt);
        if (repayAmt == debtAmt) {
            // Burn this nft
            tokens.gNft.burn(nftId);
        } else {
            tokens.gNft.updateDebt(nftId, debtAmt - repayAmt);
        }
        _transferCollateral(sender, tokens.collateralToken, collateralData);
        emit RepayGNft(sender, nftId, repayAmt, false);
    }

    // use yp to deregister debt
    function deregisterGNft(
        uint256 nftId
    ) external override isOpen nonReentrant {
        _deregisterGNft(msg.sender, nftId);
    }

    function _deregisterGNft(address sender, uint256 nftId) internal {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        (address owner, uint128 debtAmt, bytes memory collateralData) = tokens
            .gNft
            .loanInfo(nftId);
        if (sender != owner) {
            revert SenderIsNotTheGNftOwner(sender, nftId);
        }
        tokens.ft.transferFrom(sender, address(this), debtAmt);
        // Burn this nft
        tokens.gNft.burn(nftId);
        _transferCollateral(sender, tokens.collateralToken, collateralData);
        emit DeregisterGNft(sender, nftId, debtAmt);
    }

    // can use yp token?
    function liquidateGNft(uint256 nftId) external override nonReentrant {
        _liquidateGNft(msg.sender, nftId);
    }

    function _liquidateGNft(address sender, uint256 nftId) internal {
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        if (!config.liquidatable) {
            revert MarketDoNotSupportLiquidation();
        }
        if (config.deliverable && block.timestamp >= config.maturity) {
            revert CanNotLiquidateAfterMaturity();
        }

        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        (, uint128 debtAmt, bytes memory collateralData) = tokens.gNft.loanInfo(
            nftId
        );
        uint128 health = _calcHealth(debtAmt, tokens.cash, collateralData)
            .toUint128();
        if (health < config.liquidationLtv) {
            revert GNftIsHealthy(sender, nftId, health);
        }
        tokens.cash.transferFrom(sender, address(this), debtAmt);
        // Burn this nft
        tokens.gNft.burn(nftId);
        _transferCollateral(sender, tokens.collateralToken, collateralData);
        emit LiquidateGNft(sender, nftId, debtAmt);
    }

    function redeem() external virtual override nonReentrant {
        _redeem(msg.sender);
    }

    function _redeem(address sender) internal {
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        if (block.timestamp < config.maturity) {
            revert CanNotRedeemBeforeMaturity();
        }
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        // Burn all lp tokens owned by this contract after maturity to release all reward
        if (!config.rewardIsDistributed) {
            _distributeAllReward(tokens.lpFt, tokens.lpXt);
        }
        // k = (1 - initalLtv) * DECIMAL_BASE
        uint k = TermMaxCurve.DECIMAL_BASE - config.initialLtv;
        uint userPoint;
        {
            // Calculate lp tokens output
            uint lpFtAmt = tokens.lpFt.balanceOf(sender);
            if (lpFtAmt > 0) {
                tokens.lpFt.transferFrom(sender, address(this), lpFtAmt);
                uint lpFtTotalSupply = tokens.lpFt.totalSupply();
                uint ftReserve = tokens.ft.balanceOf(address(this));
                userPoint += lpFtAmt.mulDiv(ftReserve, lpFtTotalSupply);
                tokens.lpFt.burn(lpFtAmt);
            }
            uint lpXtAmt = tokens.lpXt.balanceOf(sender);
            if (lpXtAmt > 0) {
                tokens.lpXt.transferFrom(sender, address(this), lpXtAmt);
                uint lpXtTotalSupply = tokens.lpXt.totalSupply();
                uint xtReserve = tokens.xt.balanceOf(address(this));
                uint yaAmt = lpXtAmt.mulDiv(xtReserve, lpXtTotalSupply);
                userPoint += yaAmt.mulDiv(k, TermMaxCurve.DECIMAL_BASE);
                tokens.lpFt.burn(lpXtAmt);
            }
        }
        // All points = ypSupply + yaSupply * (1 - initalLtv) = ypSupply * k / DECIMAL_BASE
        uint allPoints = tokens.ft.totalSupply() +
            tokens.xt.totalSupply().mulDiv(k, TermMaxCurve.DECIMAL_BASE);
        {
            uint ypAmt = tokens.ft.balanceOf(sender);
            if (ypAmt > 0) {
                tokens.ft.transferFrom(sender, address(this), ypAmt);
                userPoint += ypAmt;
                tokens.ft.burn(ypAmt);
            }
            uint yaAmt = tokens.xt.balanceOf(sender);
            if (yaAmt > 0) {
                tokens.xt.transferFrom(sender, address(this), yaAmt);
                userPoint += yaAmt.mulDiv(k, TermMaxCurve.DECIMAL_BASE);
                tokens.xt.burn(yaAmt);
            }
        }

        // The ratio that user will get how many cash and collateral when do redeem
        uint ratio = userPoint.mulDiv(TermMaxCurve.DECIMAL_BASE, allPoints);
        bytes memory deliveryData = _deliveryCollateral(
            tokens.collateralToken,
            ratio,
            sender
        );
        // Transfer cash output
        uint cashAmt = tokens.cash.balanceOf(address(this)).mulDiv(
            ratio,
            TermMaxCurve.DECIMAL_BASE
        );
        tokens.cash.transfer(sender, cashAmt);
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

    function _distributeAllReward(
        IMintableERC20 lpFt,
        IMintableERC20 lpXt
    ) internal {
        uint lpFtBalance = lpFt.balanceOf(address(this));
        uint lpXtBalance = lpXt.balanceOf(address(this));
        if (lpFtBalance > 0) {
            lpFt.burn(lpFtBalance);
        }
        if (lpXtBalance > 0) {
            lpXt.burn(lpXtBalance);
        }
    }

    function _deliveryCollateral(
        address collateral,
        uint256 ratio,
        address to
    ) internal virtual returns (bytes memory deliveryData);

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
