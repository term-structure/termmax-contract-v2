// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IPPrincipalToken, IPMarket} from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, IERC20} from "../contracts/core/TermMaxMarket.sol";
import {MockFlashLoanReceiver} from "../contracts/test/MockFlashLoanReceiver.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {AbstractGearingToken} from "../contracts/core/tokens/AbstractGearingToken.sol";
import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken, AggregatorV3Interface} from "../contracts/core/factory/TermMaxFactory.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";
import {ISwapAdapter, UniswapV3Adapter} from "../contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "../contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
struct SwapUnit {
    address adapter;
    address tokenIn;
    address tokenOut;
    bytes swapData;
}

contract SwapAdapterTest is Test {
    using JSONLoader for *;
    using SafeCast for uint256;
    using SafeCast for int256;
    DeployUtils.Res res;

    MarketConfig marketConfig;

    address deployer = vm.randomAddress();
    address sender = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    address weth9Addr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address weethAddr = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address ptWeethMarketAddr = 0x7d372819240D14fB477f17b964f95F33BeB4c704; // 26 Dec 2024

    address pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    UniswapV3Adapter uniswapAdapter;
    PendleSwapV3Adapter pendleAdapter;

    TestRouter testRouter;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21208075); // Nov-17-2024 05:09:23 PM +UTC, 1731388163

        uniswapAdapter = new UniswapV3Adapter(uniswapRouter);
        pendleAdapter = new PendleSwapV3Adapter(pendleRouter);
        testRouter = new TestRouter();
    }

    function testDoMutipleSwaps() public {
        uint amount = 1_00e18;
        amount = 4.881e18;
        uint24 poolFee = 3000;
        deal(weth9Addr, address(this), amount);
        IERC20(weth9Addr).transfer(address(testRouter), amount);
        SwapUnit[] memory units = new SwapUnit[](3);
        units[0] = SwapUnit(
            address(uniswapAdapter),
            weth9Addr,
            weethAddr,
            abi.encode(poolFee, 0)
        );

        (, IPPrincipalToken PT, ) = IPMarket(ptWeethMarketAddr).readTokens();

        units[1] = SwapUnit(
            address(pendleAdapter),
            weethAddr,
            address(PT),
            abi.encode(ptWeethMarketAddr, 0)
        );

        units[2] = SwapUnit(
            address(pendleAdapter),
            address(PT),
            weethAddr,
            abi.encode(ptWeethMarketAddr, 0)
        );

        bytes memory tokenOutData = testRouter.swap(units, abi.encode(amount));

        uint256 netBalance = IERC20(weth9Addr).balanceOf(address(testRouter));
        assert(netBalance >= abi.decode(tokenOutData, (uint)));
    }
}

contract TestRouter {
    function swap(
        SwapUnit[] memory units,
        bytes memory tokenInData
    ) external returns (bytes memory tokenOutData) {
        for (uint i = 0; i < units.length; i++) {
            // encode datas
            bytes memory data = abi.encodeWithSelector(
                ISwapAdapter.swap.selector,
                units[i].tokenIn,
                units[i].tokenOut,
                tokenInData,
                units[i].swapData
            );

            (bool success, bytes memory returnData) = units[i]
                .adapter
                .delegatecall(data);

            require(success);

            tokenInData = abi.decode(returnData, (bytes));
        }
        tokenOutData = tokenInData;
    }
}
