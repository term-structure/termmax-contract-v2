// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract OKXScaleHelper {
    function _okxScaling(bytes memory rawCallData, uint256 actualAmount, address receiver)
        internal
        pure
        returns (bytes memory scaledCallData)
    {
        bytes4 selector;
        assembly {
            selector := mload(add(rawCallData, 32))
        }
        bytes memory dataToDecode;
        assembly {
            let len := sub(mload(rawCallData), 4)
            dataToDecode := mload(0x40)
            mstore(dataToDecode, len)
            let src := add(rawCallData, 36)
            let dest := add(dataToDecode, 32)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } { mstore(add(dest, i), mload(add(src, i))) }
            mstore(0x40, add(dest, len))
        }

        if (selector == IOKXDexRouter.uniswapV3SwapTo.selector) {
            (, uint256 amount, uint256 minReturn, uint256[] memory pools) =
                abi.decode(dataToDecode, (uint256, uint256, uint256, uint256[]));

            minReturn = (minReturn * actualAmount) / amount;
            amount = actualAmount;
            scaledCallData = abi.encodeWithSelector(selector, uint160(receiver), amount, minReturn, pools);
        } else if (selector == IOKXDexRouter.smartSwapTo.selector) {
            (
                uint256 orderId,
                ,
                IOKXDexRouter.BaseRequest memory baseRequest,
                uint256[] memory batchesAmount,
                IOKXDexRouter.RouterPath[][] memory batches,
                IOKXDexRouter.PMMSwapRequest[] memory extraData
            ) = abi.decode(
                dataToDecode,
                (
                    uint256,
                    address,
                    IOKXDexRouter.BaseRequest,
                    uint256[],
                    IOKXDexRouter.RouterPath[][],
                    IOKXDexRouter.PMMSwapRequest[]
                )
            );

            batchesAmount = _scaleArray(batchesAmount, actualAmount, baseRequest.fromTokenAmount);
            baseRequest.minReturnAmount = (baseRequest.minReturnAmount * actualAmount) / baseRequest.fromTokenAmount;
            baseRequest.fromTokenAmount = actualAmount;

            scaledCallData =
                abi.encodeWithSelector(selector, orderId, receiver, baseRequest, batchesAmount, batches, extraData);
        } else if (selector == IOKXDexRouter.unxswapTo.selector) {
            (uint256 srcToken, uint256 amount, uint256 minReturn,, bytes32[] memory pools) =
                abi.decode(dataToDecode, (uint256, uint256, uint256, address, bytes32[]));

            minReturn = (minReturn * actualAmount) / amount;
            amount = actualAmount;

            scaledCallData = abi.encodeWithSelector(selector, srcToken, amount, minReturn, receiver, pools);
        } else if (selector == IOKXDexRouter.unxswapByOrderId.selector) {
            (uint256 srcToken, uint256 amount, uint256 minReturn, bytes32[] memory pools) =
                abi.decode(dataToDecode, (uint256, uint256, uint256, bytes32[]));

            minReturn = (minReturn * actualAmount) / amount;
            amount = actualAmount;

            scaledCallData = abi.encodeWithSelector(selector, srcToken, amount, minReturn, pools);
        } else if (selector == IOKXDexRouter.smartSwapByOrderId.selector) {
            (
                uint256 orderId,
                IOKXDexRouter.BaseRequest memory baseRequest,
                uint256[] memory batchesAmount,
                IOKXDexRouter.RouterPath[][] memory batches,
                IOKXDexRouter.PMMSwapRequest[] memory extraData
            ) = abi.decode(
                dataToDecode,
                (
                    uint256,
                    IOKXDexRouter.BaseRequest,
                    uint256[],
                    IOKXDexRouter.RouterPath[][],
                    IOKXDexRouter.PMMSwapRequest[]
                )
            );

            batchesAmount = _scaleArray(batchesAmount, actualAmount, baseRequest.fromTokenAmount);
            baseRequest.minReturnAmount = (baseRequest.minReturnAmount * actualAmount) / baseRequest.fromTokenAmount;
            baseRequest.fromTokenAmount = actualAmount;

            scaledCallData = abi.encodeWithSelector(selector, orderId, baseRequest, batchesAmount, batches, extraData);
        } else if (selector == IOKXDexRouter.unxswapToWithBaseRequest.selector) {
            (uint256 orderId,, IOKXDexRouter.BaseRequest memory baseRequest, bytes32[] memory pools) =
                abi.decode(dataToDecode, (uint256, address, IOKXDexRouter.BaseRequest, bytes32[]));
            baseRequest.minReturnAmount = (baseRequest.minReturnAmount * actualAmount) / baseRequest.fromTokenAmount;
            baseRequest.fromTokenAmount = actualAmount;
            scaledCallData = abi.encodeWithSelector(selector, orderId, receiver, baseRequest, pools);
        } else if (selector == IOKXDexRouter.dagSwapByOrderId.selector) {
            (uint256 orderId, IOKXDexRouter.BaseRequest memory baseRequest, IOKXDexRouter.RouterPath[] memory paths) =
                abi.decode(dataToDecode, (uint256, IOKXDexRouter.BaseRequest, IOKXDexRouter.RouterPath[]));
            baseRequest.minReturnAmount = (baseRequest.minReturnAmount * actualAmount) / baseRequest.fromTokenAmount;
            baseRequest.fromTokenAmount = actualAmount;
            scaledCallData = abi.encodeWithSelector(selector, orderId, baseRequest, paths);
        } else if (selector == IOKXDexRouter.dagSwapTo.selector) {
            (uint256 orderId,, IOKXDexRouter.BaseRequest memory baseRequest, IOKXDexRouter.RouterPath[] memory paths) =
                abi.decode(dataToDecode, (uint256, address, IOKXDexRouter.BaseRequest, IOKXDexRouter.RouterPath[]));
            baseRequest.minReturnAmount = (baseRequest.minReturnAmount * actualAmount) / baseRequest.fromTokenAmount;
            baseRequest.fromTokenAmount = actualAmount;
            scaledCallData = abi.encodeWithSelector(selector, orderId, receiver, baseRequest, paths);
        } else {
            revert("OKX scale helper: OKX selector not supported");
        }
    }

    function _scaleArray(uint256[] memory arr, uint256 newAmount, uint256 oldAmount)
        internal
        pure
        returns (uint256[] memory scaledArr)
    {
        scaledArr = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            scaledArr[i] = (arr[i] * newAmount) / oldAmount;
        }
    }
}

interface IOKXDexRouter {
    struct BaseRequest {
        uint256 fromToken;
        address toToken;
        uint256 fromTokenAmount;
        uint256 minReturnAmount;
        uint256 deadLine;
    }

    struct RouterPath {
        address[] mixAdapters;
        address[] assetTo;
        uint256[] rawData;
        bytes[] extraData;
        uint256 fromToken;
    }

    struct PMMSwapRequest {
        uint256 pathIndex;
        address payer;
        address fromToken;
        address toToken;
        uint256 fromTokenAmountMax;
        uint256 toTokenAmountMax;
        uint256 salt;
        uint256 deadLine;
        bool isPushOrder;
        bytes extension;
    }

    function uniswapV3SwapTo(uint256 receiver, uint256 amount, uint256 minReturn, uint256[] calldata pools)
        external
        payable
        returns (uint256 returnAmount);

    function smartSwapTo(
        uint256 orderId,
        address receiver,
        BaseRequest calldata baseRequest,
        uint256[] calldata batchesAmount,
        RouterPath[][] calldata batches,
        PMMSwapRequest[] calldata extraData
    ) external payable returns (uint256 returnAmount);

    function unxswapTo(
        uint256 srcToken,
        uint256 amount,
        uint256 minReturn,
        address receiver,
        // solhint-disable-next-line no-unused-vars
        bytes32[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function unxswapByOrderId(
        uint256 srcToken,
        uint256 amount,
        uint256 minReturn,
        // solhint-disable-next-line no-unused-vars
        bytes32[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function smartSwapByOrderId(
        uint256 orderId,
        BaseRequest calldata baseRequest,
        uint256[] calldata batchesAmount,
        RouterPath[][] calldata batches,
        PMMSwapRequest[] calldata extraData
    ) external payable returns (uint256 returnAmount);

    function unxswapToWithBaseRequest(
        uint256 orderId,
        address receiver,
        BaseRequest calldata baseRequest,
        bytes32[] calldata pools
    ) external payable returns (uint256 returnAmount);

    function dagSwapByOrderId(uint256 orderId, BaseRequest calldata baseRequest, RouterPath[] calldata paths)
        external
        payable
        returns (uint256 returnAmount);

    function dagSwapTo(uint256 orderId, address receiver, BaseRequest calldata baseRequest, RouterPath[] calldata paths)
        external
        payable
        returns (uint256 returnAmount);
}
