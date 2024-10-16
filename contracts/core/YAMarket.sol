// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IYAMarket} from "../interfaces/IYAMarket.sol";
import {IERC20, IMintableERC20} from "../interfaces/IMintableERC20.sol";
import {IFlashLoanReceiver} from "../interfaces/IFlashLoanReceiver.sol";
import {YAMarketCurve} from "../lib/YAMarketCurve.sol";

contract YAMarket is IYAMarket {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    string constant PREFIX_YP = "YP:";
    string constant PREFIX_YA = "YA:";
    string constant PREFIX_LP_YP = "LpYP:";
    string constant PREFIX_LP_YA = "LpYA:";

    IMintableERC20 ya;
    IMintableERC20 yp;
    IMintableERC20 lpYa;
    IMintableERC20 lpYp;
    IERC20 collateral;
    IERC20 cash;
    //10**ya.decimals()
    uint256 mintLeveragedYa;
    uint64 maturity;
    uint64 openTime;
    int64 public apy;
    uint32 gamma;
    uint32 lendFeeRatio;
    uint32 borrowFeeRatio;
    uint32 immutable ltv; // 9e7
    uint32 immutable liquidateThreshhold; // 85e6

    modifier isOpen() {
        if (block.timestamp < openTime) {
            revert MarketIsNotOPen();
        }
        if (block.timestamp >= maturity) {
            revert MarketWasClosed();
        }
        _;
    }

    constructor(IERC20 collateralToken, IERC20 cashToken, address) {}

    function reserves()
        external
        view
        override
        returns (
            uint128 ypAmt,
            uint128 yaAmt,
            uint128 cashAmt,
            uint128 colateralAmt
        )
    {}

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
        uint ypReserve = yp.balanceOf(address(this));
        uint lpYpTotalSupply = lpYp.totalSupply();

        uint yaReserve = ya.balanceOf(address(this));
        uint lpYaTotalSupply = lpYa.totalSupply();
        (uint128 ypMintedAmt, uint128 yaMintedAmt) = _addLiquidity(
            sender,
            cashAmt
        );

        lpYpOutAmt = YAMarketCurve
            ._calculateLpOut(ypMintedAmt, ypReserve, lpYpTotalSupply)
            .toUint128();

        lpYaOutAmt = YAMarketCurve
            ._calculateLpOut(yaMintedAmt, yaReserve, lpYaTotalSupply)
            .toUint128();
        lpYa.mint(sender, lpYaOutAmt);
        lpYp.mint(sender, lpYpOutAmt);

        emit ProvideLiquidity(sender, cashAmt, lpYpOutAmt, lpYaOutAmt);
    }

    function _addLiquidity(
        address sender,
        uint256 cashAmt
    ) internal returns (uint128 ypMintedAmt, uint128 yaMintedAmt) {
        cash.transferFrom(sender, address(this), cashAmt);

        ypMintedAmt = cashAmt
            .mulDiv(ltv, YAMarketCurve.DECIMAL_BASE)
            .toUint128();
        yaMintedAmt = cashAmt.toUint128();
        // Mint tokens to this
        yp.mint(address(this), ypMintedAmt);
        ya.mint(address(this), yaMintedAmt);

        emit AddLiquidity(sender, cashAmt, ypMintedAmt, yaMintedAmt);
    }

    function _daysTomaturity() internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (maturity - block.timestamp) /
            YAMarketCurve.SECONDS_IN_DAY;
    }

    function withdrawYp(
        uint256 lpAmtIn
    ) external override isOpen returns (uint tokenOut) {
        tokenOut = _withdrawLp(msg.sender, lpYp, lpAmtIn);
    }

    function withdrawYa(
        uint256 lpAmtIn
    ) external override isOpen returns (uint tokenOut) {
        tokenOut = _withdrawLp(msg.sender, lpYa, lpAmtIn);
    }

    function _withdrawLp(
        address sender,
        LpToken lpToken,
        uint256 lpAmtIn
    ) internal returns (uint tokenOut) {
        lpToken.transferFrom(sender, address(this), lpAmtIn);
        uint ypReserve = yp.balanceOf(address(this));
        uint yaReserve = ya.balanceOf(address(this));
        uint lpTokenTotalSupply = lpToken.totalSupply();
        // calculate rewards
        uint rewards = YAMarketCurve.calculateLpReward(
            block.timestamp,
            openTime,
            maturity,
            lpTokenTotalSupply,
            lpAmtIn,
            lpToken.balanceOf(address(this))
        );
        lpAmtIn += rewards;
        lpToken.burn(lpAmtIn);
        tokenOut = lpAmtIn.mulDiv(ypReserve, lpTokenTotalSupply);
        if (lpToken == lpYp) {
            (, , apy) = YAMarketCurve._sellNegYp(
                tokenOut,
                ypReserve,
                yaReserve,
                _daysTomaturity(),
                gamma,
                ltv,
                apy
            );
            yp.transfer(sender, tokenOut);
        } else {
            (, , apy) = YAMarketCurve._sellNegYa(
                tokenOut,
                ypReserve,
                yaReserve,
                _daysTomaturity(),
                gamma,
                ltv,
                apy
            );
            ya.transfer(sender, tokenOut);
        }

        emit WithdrawLP(
            sender,
            lpToken,
            lpAmtIn.toUint128(),
            tokenOut.toUint128(),
            apy
        );
    }

    function buyYp(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, yp, cashAmtIn, minTokenOut);
    }

    function buyYa(
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) external override returns (uint256 netOut) {
        netOut = _buyToken(msg.sender, ya, cashAmtIn, minTokenOut);
    }

    function _buyToken(
        address sender,
        IMintableERC20 token,
        uint128 cashAmtIn,
        uint128 minTokenOut
    ) internal returns (uint256 netOut) {
        // Get old reserves
        uint ypReserve = yp.balanceOf(address(this));
        uint yaReserve = ya.balanceOf(address(this));
        uint feeAmt;
        // add new lituidity
        _addLiquidity(sender, cashAmtIn);
        if (token == yp) {
            (uint newYpReserve, uint newYaReserve, int64 newApy) = YAMarketCurve
                .buyYp(
                    cashAmtIn,
                    ypReserve,
                    yaReserve,
                    _daysTomaturity(),
                    gamma,
                    ltv,
                    apy
                );
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                lendFeeRatio,
                ltv
            );
            //TODO protocol rewards
            uint finalYpReserve;
            (finalYpReserve, , apy) = YAMarketCurve.buyNegYp(
                feeAmt,
                ypReserve,
                yaReserve,
                _daysTomaturity(),
                gamma,
                ltv,
                newApy
            );

            uint ypCurrentReserve = yp.balanceOf(address(this));
            netOut = ypCurrentReserve - finalYpReserve;
        } else {
            (uint newYpReserve, uint newYaReserve, int64 newApy) = YAMarketCurve
                .buyYa(
                    cashAmtIn,
                    ypReserve,
                    yaReserve,
                    _daysTomaturity(),
                    gamma,
                    ltv,
                    apy
                );
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                borrowFeeRatio,
                ltv
            );
            //TODO protocol rewards
            uint finalYaReserve;
            (finalYaReserve, , apy) = YAMarketCurve.buyNegYa(
                feeAmt,
                ypReserve,
                yaReserve,
                _daysTomaturity(),
                gamma,
                ltv,
                newApy
            );
            uint yaCurrentReserve = ya.balanceOf(address(this));
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
        _lockFee(feeAmt);
        emit BuyToken(sender, token, minTokenOut, netOut.toUint128(), apy);
    }

    function _sellToken(
        address sender,
        IMintableERC20 token,
        uint128 tokenAmtIn,
        uint128 minCashOut
    ) internal returns (uint256 netOut) {
        token.transferFrom(sender, address(this), tokenAmtIn);
        // Get old reserves
        uint ypReserve = yp.balanceOf(address(this));
        uint yaReserve = ya.balanceOf(address(this));
        uint feeAmt;
        if (token == yp) {
            (uint newYpReserve, uint newYaReserve, int64 newApy) = YAMarketCurve
                .sellYp(
                    tokenAmtIn,
                    ypReserve,
                    yaReserve,
                    _daysTomaturity(),
                    gamma,
                    ltv,
                    apy
                );
            netOut = yaReserve - newYpReserve;
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                borrowFeeRatio,
                ltv
            );
            apy = newApy;
        } else {
            (uint newYpReserve, uint newYaReserve, int64 newApy) = YAMarketCurve
                .sellYa(
                    tokenAmtIn,
                    ypReserve,
                    yaReserve,
                    _daysTomaturity(),
                    gamma,
                    ltv,
                    apy
                );
            netOut = tokenAmtIn + yaReserve - newYpReserve;
            // calculate fee
            feeAmt = YAMarketCurve.calculateFee(
                ypReserve,
                yaReserve,
                newYpReserve,
                newYaReserve,
                lendFeeRatio,
                ltv
            );
            apy = newApy;
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
        _lockFee(feeAmt);
        token.burn(tokenAmtIn);
        cash.transfer(sender, netOut);

        emit SellToken(sender, token, minCashOut, netOut.toUint128(), apy);
    }

    function _lockFee(uint256 feeAmount) internal {
        uint feeToLock = (feeAmount + 1) / 2;
        uint ypAmount = feeToLock.mulDiv(ltv, YAMarketCurve.DECIMAL_BASE);

        uint lpYpAmt = YAMarketCurve._calculateLpOut(
            ypAmount,
            yp.balanceOf(address(this)) - ypAmount,
            lpYp.totalSupply()
        );
        lpYp.mint(address(this), lpYpAmt);

        uint lpYaAmt = YAMarketCurve._calculateLpOut(
            feeToLock,
            ya.balanceOf(address(this)) - feeToLock,
            lpYa.totalSupply()
        );
        lpYa.mint(address(this), lpYaAmt);
    }

    function mintLeveragedNft(
        uint128 collateralAmt,
        uint128 yaAmt,
        bytes memory data
    ) external override returns (uint256) {}

    function _mintLeveragedNft(
        address sender,
        uint256 collateralAmt,
        uint256 yaAmt,
        bytes memory data
    ) internal returns (uint256) {
        if (yaAmt < mintLeveragedYa) {
            revert();
        }
        uint debt = yaAmt.mulDiv(ltv, YAMarketCurve.DECIMAL_BASE);
        uint collateral = collateralAmt + debt

        ya.transferFrom(sender, address(this), yaAmt);
        cash.transfer(sender, debt);
        IFlashLoanReceiver(sender).executeOperation(sender, cash, debt, )
    }
}
