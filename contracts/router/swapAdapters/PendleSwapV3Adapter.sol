// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PendleHelper} from "../lib/PendleHelper.sol";
import {IPAllActionV3} from "@pendle/core-v2/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket, IPPrincipalToken} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import "./ERC20OutputAdapter.sol";

contract PendleSwapV3Adapter is ERC20OutputAdapter, PendleHelper {
    IPAllActionV3 public immutable router;

    // IPAllActionV3(0x888888888889758F76e7103c6CbF23ABbF58F946);

    constructor(address router_) {
        router = IPAllActionV3(router_);
    }

    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory tokenInData,
        bytes memory swapData
    ) external override returns (bytes memory tokenOutData) {
        (address ptMarketAddr, uint256 minTokenOut) = abi.decode(
            swapData,
            (address, uint256)
        );
        IPMarket market = IPMarket(ptMarketAddr);

        (, IPPrincipalToken PT, ) = market.readTokens();
        uint amount = _decodeAmount(tokenInData);
        IERC20(tokenIn).approve(address(router), amount);
        if (tokenOut == address(PT)) {
            (uint256 netPtOut, , ) = router.swapExactTokenForPt(
                address(this),
                address(market),
                minTokenOut,
                defaultApprox,
                createTokenInputStruct(tokenIn, amount),
                emptyLimit
            );
            return _encodeAmount(netPtOut);
        } else {
            (uint256 netPtOut, , ) = router.swapExactPtForToken(
                address(this),
                address(market),
                amount,
                createTokenOutputStruct(tokenOut, minTokenOut),
                emptyLimit
            );
            return _encodeAmount(netPtOut);
        }
    }
}
