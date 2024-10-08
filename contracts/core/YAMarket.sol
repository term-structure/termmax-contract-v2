// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IYAMarket} from "../interfaces/IYAMarket.sol";
import {IERC20, IMintableERC20} from "../interfaces/IMintableERC20.sol";

contract YAMarket is IYAMarket {
    using Math for uint256;
    using SafeCast for uint256;

    IMintableERC20 ya;
    IMintableERC20 yp;
    IMintableERC20 lpYa;
    IMintableERC20 lpYp;
    IERC20 collateral;
    IERC20 cash;
    uint64 maturity;
    uint32 public interest;
    uint32 immutable ltvNumerator; // 9e7

    uint32 constant LTV_BASE = 1e8;
    uint32 constant ONE_DAY_SECONDS = 86400;
    uint32 constant ONE_YEAR_DAYS = 365;

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
        address lpReceiver
    ) external returns (uint128 lpYaOutAmt, uint128 lpYpOutAmt) {
        cash.transferFrom(msg.sender, address(this), cashAmt);
        if (lpReceiver == address(0)) {
            (, lpYaOutAmt, , lpYpOutAmt) = _mintLp(cashAmt, msg.sender);
        } else {
            (, lpYaOutAmt, , lpYpOutAmt) = _mintLp(cashAmt, lpReceiver);
        }
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

    function _calculateLpOut(
        IMintableERC20 token,
        uint256 tokenIn,
        IMintableERC20 lpToken
    ) internal view returns (uint128 lpOutAmt) {
        uint256 lpTotalSupply = lpToken.totalSupply();
        if (lpTotalSupply == 0) {
            lpOutAmt = tokenIn.toUint128();
        } else {
            // lpOutAmt = tokenIn/(tokenReserve/lpTotalSupply) = tokenIn*lpTotalSupply/tokenReserve
            uint256 tokenReserve = token.balanceOf(address(this));
            lpOutAmt = tokenIn.mulDiv(lpTotalSupply, tokenReserve).toUint128();
        }
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
        // yaAmt = cashAmt
        yaMintedAmt = cashAmt.toUint128();
        lpYaOutAmt = _calculateLpOut(ya, yaMintedAmt, lpYa);

        //ypAmt = (cashAmt*ltvNumerator)/(LTV_BASE + APY*dayTomaturity*LTV_BASE/365)
        uint dayTomaturity = (maturity - block.timestamp) / ONE_DAY_SECONDS;
        ypMintedAmt = cashAmt
            .mulDiv(
                ltvNumerator,
                (LTV_BASE +
                    uint256(interest).mulDiv(dayTomaturity, ONE_YEAR_DAYS))
            )
            .toUint128();
        lpYpOutAmt = _calculateLpOut(yp, ypMintedAmt, lpYp);
    }

    function swap(
        address tokenIn,
        uint128 amtIn,
        uint128 minAmtOut
    ) external override returns (uint256 netAmtOut) {}

    function withdrawYa(uint128 lpAmtIn) external override {}

    function withdrawYp(uint128 lpAmtIn) external override {}
}
