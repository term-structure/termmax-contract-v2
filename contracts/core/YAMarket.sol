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
        cash.transferFrom(msg.sender, address(this), cashAmt);
        if (receiver == address(0)) {
            receiver = msg.sender;
        }
        uint128 yaMintedAmt;
        uint128 ypMintedAmt;
        (yaMintedAmt, lpYaOutAmt, ypMintedAmt, lpYpOutAmt) = _mintLp(
            cashAmt,
            receiver
        );
        emit AddLiquidity(
            receiver,
            cashAmt,
            ypMintedAmt,
            lpYpOutAmt,
            yaMintedAmt,
            lpYaOutAmt
        );
    }

    function _mintLp(
        uint256 cashAmt,
        address lpReceiver
    )
        internal
        returns (
            uint128 yaMintedAmt,
            uint128 lpYaOutAmt,
            uint128 ypMintedAmt,
            uint128 lpYpOutAmt
        )
    {
        (yaMintedAmt, lpYaOutAmt, ypMintedAmt, lpYpOutAmt) = predictLpOut(
            cashAmt
        );

        // Mint ya token to this
        ya.mint(address(this), yaMintedAmt);
        // Mint lpYa token to the lpReceiver
        lpYa.mint(lpReceiver, lpYaOutAmt);
        // Mint yp token to this
        yp.mint(address(this), ypMintedAmt);
        // Mint lpYp token to the lpReceiver
        lpYp.mint(lpReceiver, lpYpOutAmt);
    }

    function predictLpOut(
        uint256 cashAmt
    )
        public
        view
        returns (
            uint128 yaMintedAmt,
            uint128 lpYaOutAmt,
            uint128 ypMintedAmt,
            uint128 lpYpOutAmt
        )
    {
        uint256 ypReserve = yp.balanceOf(address(this));
        uint256 lpYpTotalSupply = lpYp.totalSupply();
        uint256 yaReserve = ya.balanceOf(address(this));
        uint256 lpYaTotalSupply = lpYa.totalSupply();
        (yaMintedAmt, lpYaOutAmt, ypMintedAmt, lpYpOutAmt) = YAMarketCurve
            ._predictLpOut(
                cashAmt,
                _daysTomaturity(),
                ypReserve,
                lpYpTotalSupply,
                yaReserve,
                lpYaTotalSupply,
                ltv,
                apy
            );
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

    function withdrawYa(uint256 lpAmtIn, address receiver) external override {}

    function withdrawYp(uint256 lpAmtIn, address receiver) external override {
        lpYp.transferFrom(msg.sender, address(this), lpAmtIn);

        uint ypReserve = yp.balanceOf(address(this));
        uint lpYpTotalSupply = lpYp.totalSupply();
        uint removedYp = lpAmtIn.mulDiv(ypReserve, lpYpTotalSupply);

        apy = YAMarketCurve._calcSellNegYp(
            removedYp,
            ypReserve,
            _daysTomaturity(),
            gamma,
            ltv,
            apy
        );
        lpYp.burn(lpAmtIn);
        ya.transfer(receiver, removedYp);
    }
}
