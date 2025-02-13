// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";

contract MarketViewer {
    struct LoanPosition {
        uint256 loanId;
        uint256 collateralAmt;
        uint256 debtAmt;
    }

    struct Position {
        uint256 underlyingBalance;
        uint256 collateralBalance;
        uint256 ftBalance;
        uint256 xtBalance;
        uint256 lpFtBalance;
        uint256 lpXtBalance;
        LoanPosition[] gtInfo;
    }

    function getPositionDetail(ITermMaxMarket market, address owner) external view returns (Position memory position) {
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateral, IERC20 underlying) =
            market.tokens();
        position.underlyingBalance = underlying.balanceOf(owner);
        position.collateralBalance = IERC20(collateral).balanceOf(owner);
        position.ftBalance = ft.balanceOf(owner);
        position.xtBalance = xt.balanceOf(owner);

        IERC721Enumerable gtNft = IERC721Enumerable(address(gt));
        uint256 balance = gtNft.balanceOf(owner);
        position.gtInfo = new LoanPosition[](balance);

        for (uint256 i = 0; i < balance; ++i) {
            uint256 loanId = gtNft.tokenOfOwnerByIndex(owner, i);
            position.gtInfo[i].loanId = loanId;
            (, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(loanId);
            position.gtInfo[i].debtAmt = debtAmt;
            position.gtInfo[i].collateralAmt = _decodeAmount(collateralData);
        }
    }

    function getAllLoanPosition(ITermMaxMarket market, address owner) external view returns (LoanPosition[] memory) {
        (,, IGearingToken gt,,) = market.tokens();
        IERC721Enumerable gtNft = IERC721Enumerable(address(gt));
        uint256 balance = gtNft.balanceOf(owner);
        LoanPosition[] memory loanPositions = new LoanPosition[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            uint256 loanId = gtNft.tokenOfOwnerByIndex(owner, i);
            (, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(loanId);
            loanPositions[i].loanId = loanId;
            loanPositions[i].debtAmt = debtAmt;
            loanPositions[i].collateralAmt = _decodeAmount(collateralData);
        }
        return loanPositions;
    }

    function getOrderState(ITermMaxOrder order) external view returns (OrderState memory orderState) {
        ITermMaxMarket market = order.market();
        (,, IGearingToken gt,,) = market.tokens();

        (OrderConfig memory orderConfig) = order.orderConfig();
        (uint256 ftReserve, uint256 xtReserve) = order.tokenReserves();
        if(orderConfig.gtId != 0) {
            (, uint128 debtAmt,, bytes memory collateralData) = gt.loanInfo(orderConfig.gtId);
            orderState.collateralReserve = _decodeAmount(collateralData);
            orderState.debtReserve = debtAmt;
        }

        orderState.ftReserve = ftReserve;
        orderState.xtReserve = xtReserve;
        orderState.maxXtReserve = orderConfig.maxXtReserve;
        orderState.gtId = orderConfig.gtId;
        orderState.curveCuts = orderConfig.curveCuts;
        orderState.feeConfig = orderConfig.feeConfig;
        return orderState;
    }

    function _decodeAmount(bytes memory collateralData) internal pure returns (uint256) {
        return abi.decode(collateralData, (uint256));
    }
}
