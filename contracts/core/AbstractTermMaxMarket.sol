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
import {YAMarketCurve} from "./lib/YAMarketCurve.sol";
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

    string constant PREFIX_YP = "YP:";
    string constant PREFIX_YA = "YA:";
    string constant PREFIX_LP_YP = "LpYP:";
    string constant PREFIX_LP_YA = "LpYA:";

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

    constructor(IERC20 collateralToken, IERC20 cashToken, address) {}

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
        returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt)
    {
        (lpYaOutAmt, lpYpOutAmt) = _provideLiquidity(msg.sender, cashAmt);
    }

    function _provideLiquidity(
        address sender,
        uint256 cashAmt
    ) internal returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        uint ypReserve = tokens.yp.balanceOf(address(this));
        uint lpYpTotalSupply = tokens.lpYp.totalSupply();

        uint yaReserve = tokens.ya.balanceOf(address(this));
        uint lpYaTotalSupply = tokens.lpYa.totalSupply();
        (uint128 ypMintedAmt, uint128 yaMintedAmt) = _addLiquidity(
            sender,
            cashAmt,
            config.initialLtv,
            tokens
        );

        lpYpOutAmt = YAMarketCurve
            ._calculateLpOut(ypMintedAmt, ypReserve, lpYpTotalSupply)
            .toUint128();

        lpYaOutAmt = YAMarketCurve
            ._calculateLpOut(yaMintedAmt, yaReserve, lpYaTotalSupply)
            .toUint128();
        tokens.lpYa.mint(sender, lpYaOutAmt);
        tokens.lpYp.mint(sender, lpYpOutAmt);

        emit ProvideLiquidity(sender, cashAmt, lpYpOutAmt, lpYaOutAmt);
    }

    function _addLiquidity(
        address sender,
        uint256 cashAmt,
        uint256 ltv,
        TermMaxStorage.MarketTokens memory tokens
    ) internal returns (uint128 ypMintedAmt, uint128 yaMintedAmt) {
        tokens.cash.transferFrom(sender, address(this), cashAmt);

        ypMintedAmt = cashAmt
            .mulDiv(ltv, YAMarketCurve.DECIMAL_BASE)
            .toUint128();
        yaMintedAmt = cashAmt.toUint128();
        // Mint tokens to this
        tokens.yp.mint(address(this), ypMintedAmt);
        tokens.ya.mint(address(this), yaMintedAmt);

        emit AddLiquidity(sender, cashAmt, ypMintedAmt, yaMintedAmt);
    }

    function _daysTomaturity(
        uint maturity
    ) internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (maturity - block.timestamp) /
            YAMarketCurve.SECONDS_IN_DAY;
    }

    function withdrawLp(
        uint128 lpYpAmt,
        uint128 lpYaAmt
    )
        external
        override
        isOpen
        nonReentrant
        returns (uint128 ypOutAmt, uint128 yaOutAmt)
    {
        (ypOutAmt, yaOutAmt) = _withdrawLp(msg.sender, lpYpAmt, lpYaAmt);
    }

    function _withdrawLp(
        address sender,
        uint256 lpYpAmt,
        uint256 lpYaAmt
    ) internal returns (uint128 ypOutAmt, uint128 yaOutAmt) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        // get token reserves
        uint ypReserve = tokens.yp.balanceOf(address(this));
        uint yaReserve = tokens.ya.balanceOf(address(this));
        uint lpYpTotalSupply;
        uint lpYaTotalSupply;
        // calculate reward
        if (lpYpAmt > 0) {
            tokens.lpYp.transferFrom(sender, address(this), lpYpAmt);

            lpYpTotalSupply = tokens.lpYp.totalSupply();
            uint reward = YAMarketCurve.calculateLpReward(
                block.timestamp,
                config.openTime,
                config.maturity,
                lpYpTotalSupply,
                lpYpAmt,
                tokens.lpYp.balanceOf(address(this))
            );
            lpYpAmt += reward;
            tokens.lpYp.burn(lpYpAmt);
            ypOutAmt = lpYpAmt.mulDiv(ypReserve, lpYpTotalSupply).toUint128();
        }
        if (lpYaAmt > 0) {
            tokens.lpYa.transferFrom(sender, address(this), lpYaAmt);

            lpYaTotalSupply = tokens.lpYa.totalSupply();
            uint reward = YAMarketCurve.calculateLpReward(
                block.timestamp,
                config.openTime,
                config.maturity,
                lpYaTotalSupply,
                lpYaAmt,
                tokens.lpYa.balanceOf(address(this))
            );
            lpYaAmt += reward;
            tokens.lpYa.burn(lpYaAmt);
            yaOutAmt = lpYaAmt.mulDiv(yaReserve, lpYaTotalSupply).toUint128();
        }
        uint sameProportionYp = uint(yaOutAmt).mulDiv(
            config.initialLtv,
            YAMarketCurve.DECIMAL_BASE
        );
        if (sameProportionYp > ypOutAmt) {
            uint yaExcess = (sameProportionYp - ypOutAmt).mulDiv(
                YAMarketCurve.DECIMAL_BASE,
                config.initialLtv
            );
            YAMarketCurve.TradeParams memory tradeParams = YAMarketCurve
                .TradeParams(
                    yaExcess,
                    ypReserve,
                    yaReserve,
                    _daysTomaturity(config.maturity)
                );
            (, , config.apy) = YAMarketCurve._sellNegYa(tradeParams, config);
        } else if (sameProportionYp < ypOutAmt) {
            uint ypExcess = ypOutAmt - sameProportionYp;
            YAMarketCurve.TradeParams memory tradeParams = YAMarketCurve
                .TradeParams(
                    ypExcess,
                    ypReserve,
                    yaReserve,
                    _daysTomaturity(config.maturity)
                );
            (, , config.apy) = YAMarketCurve._sellNegYp(tradeParams, config);
        }
        TermMaxStorage._getConfig().apy = config.apy;
        if (ypOutAmt > 0) {
            tokens.ya.transfer(sender, ypOutAmt);
        }
        if (yaOutAmt > 0) {
            tokens.yp.transfer(sender, yaOutAmt);
        }
        emit WithdrawLP(
            sender,
            lpYpAmt.toUint128(),
            lpYaAmt.toUint128(),
            ypOutAmt,
            yaOutAmt,
            config.apy
        );
    }

    function buyYp(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        netOut = _buyToken(
            msg.sender,
            tokens.yp,
            cashAmtIn,
            minTokenOut,
            tokens
        );
    }

    function buyYa(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override nonReentrant returns (uint256 netOut) {
        TermMaxStorage.MarketTokens memory tokens = TermMaxStorage._getTokens();
        netOut = _buyToken(
            msg.sender,
            tokens.ya,
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
        uint ypReserve = tokens.yp.balanceOf(address(this));
        uint yaReserve = tokens.ya.balanceOf(address(this));

        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        YAMarketCurve.TradeParams memory tradeParams = YAMarketCurve
            .TradeParams(
                cashAmtIn,
                ypReserve,
                yaReserve,
                _daysTomaturity(config.maturity)
            );

        uint feeAmt;
        // add new lituidity
        _addLiquidity(sender, cashAmtIn, config.initialLtv, tokens);
        if (token == tokens.yp) {
            uint newYpReserve;
            uint newYaReserve;
            (newYpReserve, newYaReserve, config.apy) = YAMarketCurve.buyYp(
                tradeParams,
                config
            );
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                config.lendFeeRatio,
                config.initialLtv
            );
            //TODO protocol reward
            uint finalYpReserve;
            (finalYpReserve, , config.apy) = YAMarketCurve.buyNegYp(
                YAMarketCurve.TradeParams(
                    feeAmt,
                    ypReserve,
                    yaReserve,
                    tradeParams.daysToMaturity
                ),
                config
            );

            uint ypCurrentReserve = tokens.yp.balanceOf(address(this));
            netOut = ypCurrentReserve - finalYpReserve;
        } else {
            uint newYpReserve;
            uint newYaReserve;
            (newYpReserve, newYaReserve, config.apy) = YAMarketCurve.buyYa(
                tradeParams,
                config
            );
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                config.borrowFeeRatio,
                config.initialLtv
            );
            //TODO protocol reward
            uint finalYaReserve;
            (finalYaReserve, , config.apy) = YAMarketCurve.buyNegYa(
                YAMarketCurve.TradeParams(
                    feeAmt,
                    ypReserve,
                    yaReserve,
                    tradeParams.daysToMaturity
                ),
                config
            );
            uint yaCurrentReserve = tokens.ya.balanceOf(address(this));
            netOut = yaCurrentReserve - finalYaReserve;
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
        uint ypReserve = tokens.yp.balanceOf(address(this));
        uint yaReserve = tokens.ya.balanceOf(address(this));
        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        YAMarketCurve.TradeParams memory tradeParams = YAMarketCurve
            .TradeParams(
                tokenAmtIn,
                ypReserve,
                yaReserve,
                _daysTomaturity(config.maturity)
            );
        uint feeAmt;
        if (token == tokens.yp) {
            uint newYpReserve;
            uint newYaReserve;
            (newYpReserve, newYaReserve, config.apy) = YAMarketCurve.sellYp(
                tradeParams,
                config
            );
            netOut = yaReserve - newYpReserve;
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                config.borrowFeeRatio,
                config.initialLtv
            );
        } else {
            uint newYpReserve;
            uint newYaReserve;
            (newYpReserve, newYaReserve, config.apy) = YAMarketCurve.sellYa(
                tradeParams,
                config
            );
            netOut = tokenAmtIn + yaReserve - newYpReserve;
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
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
            YAMarketCurve.DECIMAL_BASE
        );

        uint lpYpAmt = YAMarketCurve._calculateLpOut(
            ypAmount,
            tokens.yp.balanceOf(address(this)) - ypAmount,
            tokens.lpYp.totalSupply()
        );
        tokens.lpYp.mint(address(this), lpYpAmt);

        uint lpYaAmt = YAMarketCurve._calculateLpOut(
            feeToLock,
            tokens.ya.balanceOf(address(this)) - feeToLock,
            tokens.lpYa.totalSupply()
        );
        tokens.lpYa.mint(address(this), lpYaAmt);
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
        tokens.ya.transferFrom(sender, address(this), yaAmt);

        TermMaxStorage.MarketConfig memory config = TermMaxStorage._getConfig();
        if (yaAmt < config.minLeveragedYa) {
            revert XTAmountTooLittle(sender, yaAmt, collateralData);
        }
        uint debt = (yaAmt * config.initialLtv) / YAMarketCurve.DECIMAL_BASE;
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
        health = debtAmt.mulDiv(YAMarketCurve.DECIMAL_BASE, collateralValue);
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
    //     health = debtAmt.mulDiv(YAMarketCurve.DECIMAL_BASE, collateralValue);
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
        if (debtAmt < config.minLeveredYp) {
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

        tokens.yp.mint(sender, debtAmt);
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
        tokens.yp.transferFrom(sender, address(this), debtAmt);
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
            _distributeAllReward(tokens.lpYp, tokens.lpYa);
        }
        // k = (1 - initalLtv) * DECIMAL_BASE
        uint k = YAMarketCurve.DECIMAL_BASE - config.initialLtv;
        uint userPoint;
        {
            // Calculate lp tokens output
            uint lpYpAmt = tokens.lpYp.balanceOf(sender);
            if (lpYpAmt > 0) {
                tokens.lpYp.transferFrom(sender, address(this), lpYpAmt);
                uint lpYpTotalSupply = tokens.lpYp.totalSupply();
                uint ypReserve = tokens.yp.balanceOf(address(this));
                userPoint += lpYpAmt.mulDiv(ypReserve, lpYpTotalSupply);
                tokens.lpYp.burn(lpYpAmt);
            }
            uint lpYaAmt = tokens.lpYa.balanceOf(sender);
            if (lpYaAmt > 0) {
                tokens.lpYa.transferFrom(sender, address(this), lpYaAmt);
                uint lpYaTotalSupply = tokens.lpYa.totalSupply();
                uint yaReserve = tokens.ya.balanceOf(address(this));
                uint yaAmt = lpYaAmt.mulDiv(yaReserve, lpYaTotalSupply);
                userPoint += yaAmt.mulDiv(k, YAMarketCurve.DECIMAL_BASE);
                tokens.lpYp.burn(lpYaAmt);
            }
        }
        // All points = ypSupply + yaSupply * (1 - initalLtv) = ypSupply * k / DECIMAL_BASE
        uint allPoints = tokens.yp.totalSupply() +
            tokens.ya.totalSupply().mulDiv(k, YAMarketCurve.DECIMAL_BASE);
        {
            uint ypAmt = tokens.yp.balanceOf(sender);
            if (ypAmt > 0) {
                tokens.yp.transferFrom(sender, address(this), ypAmt);
                userPoint += ypAmt;
                tokens.yp.burn(ypAmt);
            }
            uint yaAmt = tokens.ya.balanceOf(sender);
            if (yaAmt > 0) {
                tokens.ya.transferFrom(sender, address(this), yaAmt);
                userPoint += yaAmt.mulDiv(k, YAMarketCurve.DECIMAL_BASE);
                tokens.ya.burn(yaAmt);
            }
        }

        // The ratio that user will get how many cash and collateral when do redeem
        uint ratio = userPoint.mulDiv(YAMarketCurve.DECIMAL_BASE, allPoints);
        bytes memory deliveryData = _deliveryCollateral(
            tokens.collateralToken,
            ratio,
            sender
        );
        // Transfer cash output
        uint cashAmt = tokens.cash.balanceOf(address(this)).mulDiv(
            ratio,
            YAMarketCurve.DECIMAL_BASE
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
        IMintableERC20 lpYp,
        IMintableERC20 lpYa
    ) internal {
        uint lpYpBalance = lpYp.balanceOf(address(this));
        uint lpYaBalance = lpYa.balanceOf(address(this));
        if (lpYpBalance > 0) {
            lpYp.burn(lpYpBalance);
        }
        if (lpYaBalance > 0) {
            lpYa.burn(lpYaBalance);
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
