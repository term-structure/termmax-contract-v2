// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IYAMarket} from "../interfaces/IYAMarket.sol";
import {IERC20, IMintableERC20} from "../interfaces/IMintableERC20.sol";

import {YAMarketCurve} from "../lib/YAMarketCurve.sol";

contract YAMarket is IYAMarket {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    IMintableERC20 ya;
    IMintableERC20 yp;
    IMintableERC20 lpYa;
    IMintableERC20 lpYp;
    IERC20 collateral;
    IERC20 cash;
    uint64 maturity;
    int64 public apy;
    uint32 gamma;
    uint32 immutable ltv; // 9e7

    modifier notExpired() {
        if (block.timestamp >= maturity) {
            revert MarketIsExpired();
        }
        _;
    }

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
        uint256 cashAmt,
        address receiver
    ) external notExpired returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt) {
        uint ypReserve = yp.balanceOf(address(this));
        uint lpYpTotalSupply = lpYp.totalSupply();

        uint yaReserve = ya.balanceOf(address(this));
        uint lpYaTotalSupply = lpYa.totalSupply();
        (uint128 ypMintedAmt, uint128 yaMintedAmt) = _addLiquidity(cashAmt);

        lpYpOutAmt = YAMarketCurve._calculateLpOut(
            ypReserve,
            ypMintedAmt,
            lpYpTotalSupply
        );

        lpYaOutAmt = YAMarketCurve._calculateLpOut(
            yaReserve,
            yaMintedAmt,
            lpYaTotalSupply
        );
        // mint LP tokens
        if (receiver == address(0)) {
            receiver = msg.sender;
        }
        lpYa.mint(receiver, lpYaOutAmt);
        lpYp.mint(receiver, lpYpOutAmt);

        emit ProvideLiquidity(receiver, cashAmt, lpYpOutAmt, lpYaOutAmt);
    }

    function _addLiquidity(
        uint256 cashAmt
    ) internal returns (uint128 ypMintedAmt, uint128 yaMintedAmt) {
        cash.transferFrom(msg.sender, address(this), cashAmt);

        ypMintedAmt = cashAmt
            .mulDiv(ltv, YAMarketCurve.DECIMAL_BASE)
            .toUint128();
        yaMintedAmt = cashAmt.toUint128();
        // Mint tokens to this
        yp.mint(address(this), ypMintedAmt);
        ya.mint(address(this), yaMintedAmt);

        emit AddLiquidity(msg.sender, cashAmt, ypMintedAmt, yaMintedAmt);
    }

    function _daysTomaturity() internal view returns (uint256 daysToMaturity) {
        daysToMaturity =
            (maturity - block.timestamp) /
            YAMarketCurve.SECONDS_IN_DAY;
    }

    function swap(
        address tokenIn,
        uint128 amtIn,
        uint128 minAmtOut
    ) external override returns (uint256 netAmtOut) {}

    function withdrawYa(uint256 lpAmtIn, address receiver) external override {
        lpYa.transferFrom(msg.sender, address(this), lpAmtIn);
        uint yaReserve = ya.balanceOf(address(this));
        uint lpYaTotalSupply = lpYa.totalSupply();
        uint removedYa = lpAmtIn.mulDiv(yaReserve, lpYaTotalSupply);

        uint ypReserve = yp.balanceOf(address(this));
        apy = YAMarketCurve._sellNegYaApy(
            removedYa,
            ypReserve,
            _daysTomaturity(),
            gamma,
            ltv,
            apy
        );
        lpYa.burn(lpAmtIn);
        ya.transfer(receiver, removedYa);
    }

    function withdrawYp(uint256 lpAmtIn, address receiver) external override {
        lpYp.transferFrom(msg.sender, address(this), lpAmtIn);

        uint ypReserve = yp.balanceOf(address(this));
        uint lpYpTotalSupply = lpYp.totalSupply();
        uint removedYp = lpAmtIn.mulDiv(ypReserve, lpYpTotalSupply);

        apy = YAMarketCurve._sellNegYpApy(
            removedYp,
            ypReserve,
            _daysTomaturity(),
            gamma,
            ltv,
            apy
        );
        lpYp.burn(lpAmtIn);
        yp.transfer(receiver, removedYp);
    }
}
