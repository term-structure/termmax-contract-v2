// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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

abstract contract AbstractTermMaxMarket is ITermMaxMarket {
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

    // input cash
    // output lp tokens
    function provideLiquidity(
        uint256 cashAmt
    ) external isOpen returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt) {
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
            config.ltv,
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
    ) external override isOpen returns (uint128 ypOutAmt, uint128 yaOutAmt) {
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
        // calculate rewards
        if (lpYpAmt > 0) {
            tokens.lpYp.transferFrom(sender, address(this), lpYpAmt);

            lpYpTotalSupply = tokens.lpYp.totalSupply();
            uint rewards = YAMarketCurve.calculateLpReward(
                block.timestamp,
                config.openTime,
                config.maturity,
                lpYpTotalSupply,
                lpYpAmt,
                tokens.lpYp.balanceOf(address(this))
            );
            lpYpAmt += rewards;
            tokens.lpYp.burn(lpYpAmt);
            ypOutAmt = lpYpAmt.mulDiv(ypReserve, lpYpTotalSupply).toUint128();
        }
        if (lpYaAmt > 0) {
            tokens.lpYa.transferFrom(sender, address(this), lpYaAmt);

            lpYaTotalSupply = tokens.lpYa.totalSupply();
            uint rewards = YAMarketCurve.calculateLpReward(
                block.timestamp,
                config.openTime,
                config.maturity,
                lpYaTotalSupply,
                lpYaAmt,
                tokens.lpYa.balanceOf(address(this))
            );
            lpYaAmt += rewards;
            tokens.lpYa.burn(lpYaAmt);
            yaOutAmt = lpYaAmt.mulDiv(yaReserve, lpYaTotalSupply).toUint128();
        }
        uint sameProportionYp = uint(yaOutAmt).mulDiv(
            config.ltv,
            YAMarketCurve.DECIMAL_BASE
        );
        if (sameProportionYp > ypOutAmt) {
            uint yaExcess = (sameProportionYp - ypOutAmt).mulDiv(
                YAMarketCurve.DECIMAL_BASE,
                config.ltv
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
    ) external override returns (uint256 netOut) {
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
    ) external override returns (uint256 netOut) {
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
        _addLiquidity(sender, cashAmtIn, config.ltv, tokens);
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
                config.ltv
            );
            //TODO protocol rewards
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
                config.ltv
            );
            //TODO protocol rewards
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
                config.ltv
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
                config.ltv
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
        //TODO protcol rewards
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
            config.ltv,
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

    function mintLeveragedNft(
        uint128 yaAmt,
        bytes calldata collateralData
    ) external override returns (uint256 nftId) {}

    function _mintLeveragedNft(
        address sender,
        uint256 collateralAmt,
        uint256 yaAmt,
        bytes memory data
    ) internal returns (uint256 nftId) {
        // if (yaAmt < minLeveragedYa) {
        //     revert();
        // }
        // uint debt = yaAmt.mulDiv(ltv, YAMarketCurve.DECIMAL_BASE);
        // if (!_checkHealth(debt, collateralAmt)) {
        //     revert();
        // }
        // ya.transferFrom(sender, address(this), yaAmt);
        // // TODO fee
        // cash.transfer(sender, debt);
        // try
        //     IFlashLoanReceiver(sender).executeOperation(
        //         sender,
        //         cash,
        //         debt,
        //         data
        //     )
        // {} catch Error(string memory err) {
        //     revert FlashloanFailedLogString(err);
        // } catch (bytes memory err) {
        //     revert FlashloanFailedLogBytes(err);
        // }
    }

    function _calcHealth(
        uint256 debtAmt,
        uint256 collateralAmt,
        TermMaxStorage.MarketConfig memory config,
        TermMaxStorage.MarketTokens memory tokens
    ) internal view returns (uint256 health) {
        // Get the price collateralToken/cash
        (, int collateralPrice, , , ) = config
            .collateralOracle
            .latestRoundData();
        uint decimals = IERC20Metadata(address(tokens.cash)).decimals();
        uint collateralValue = collateralAmt.mulDiv(
            collateralPrice.toUint256(),
            10 ** decimals
        );
        health = debtAmt.mulDiv(YAMarketCurve.DECIMAL_BASE, collateralValue);
    }

    function lever(
        uint128 debtAmt,
        bytes calldata collateralData
    ) external override returns (uint256 nftId) {}

    function repayDebt(uint256 nftId, uint256 repayAmt) external override {}

    function liquidate(uint256 nftId) external override {}

    function deregister(uint256 nftId) external override {}

    function redeem() external override returns (uint256) {}
}
