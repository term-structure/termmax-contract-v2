// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PendleHelper} from "../lib/PendleHelper.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import "./ERC20OutputAdapter.sol";

contract PendleSwapV3Adapter is ERC20OutputAdapter, PendleHelper {
    IPAllActionV3 public constant pendleRouter =
        IPAllActionV3(0x888888888889758F76e7103c6CbF23ABbF58F946);

    function swap(
        address tokenIn,
        address,
        bytes memory tokenInData,
        bytes memory swapData
    ) external override returns (bytes memory tokenOutData) {
        (address ptMarketAddr, uint256 minPtOut) = abi.decode(
            swapData,
            (address, uint256)
        );
        IPMarket market = IPMarket(ptMarketAddr);

        uint amount = _decodeAmount(tokenInData);

        IERC20(tokenIn).approve(address(pendleRouter), amount);

        (uint256 netPtOut, , ) = pendleRouter.swapExactTokenForPt(
            address(this),
            address(market),
            minPtOut,
            defaultApprox,
            createTokenInputStruct(tokenIn, amount),
            emptyLimit
        );
        return _encodeAmount(netPtOut);
    }
}
