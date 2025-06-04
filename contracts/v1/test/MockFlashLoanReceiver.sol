// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITermMaxMarket, IFlashLoanReceiver, IGearingToken, IERC20} from "../TermMaxMarket.sol";

contract MockFlashLoanReceiver is IFlashLoanReceiver {
    ITermMaxMarket market;
    IGearingToken gt;
    address collateral;
    IERC20 underlying;
    IERC20 xt;

    constructor(ITermMaxMarket market_) {
        market = market_;

        (, xt, gt, collateral, underlying) = market.tokens();
    }

    function executeOperation(address gtReceiver, IERC20 asset, uint256 amount, bytes calldata data)
        external
        override
        returns (bytes memory collateralData)
    {
        (address caller, uint256 collateralAmt) = abi.decode(data, (address, uint256));
        IERC20(collateral).approve(address(gt), collateralAmt);

        assert(gtReceiver == caller);
        assert(asset == underlying);
        assert(asset.balanceOf(address(this)) == amount);

        collateralData = abi.encode(collateralAmt);
    }

    function leverageByXt(uint128 xtAmt, bytes calldata callbackData) external returns (uint256 gtId) {
        xt.transferFrom(msg.sender, address(this), xtAmt);
        xt.approve(address(market), xtAmt);
        gtId = market.leverageByXt(msg.sender, xtAmt, callbackData);
    }
}
