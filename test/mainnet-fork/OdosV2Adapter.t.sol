// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {DeployUtils} from "../utils/DeployUtils.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import {StateChecker} from "../utils/StateChecker.sol";
import {SwapUtils} from "../utils/SwapUtils.sol";

import {ITermMaxMarket, TermMaxMarket, Constants, TermMaxCurve} from "contracts/core/TermMaxMarket.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";

import {ITermMaxFactory, TermMaxFactory, IMintableERC20, IGearingToken} from "contracts/core/factory/TermMaxFactory.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import {MarketConfig} from "contracts/core/storage/TermMaxStorage.sol";
import {TermMaxRouter, ISwapAdapter, ITermMaxRouter, SwapUnit} from "contracts/router/TermMaxRouter.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {OdosV2Adapter, IOdosRouterV2} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OdosV2AdapterMock is OdosV2Adapter {
  using SafeERC20 for IERC20;
  constructor(address router_) OdosV2Adapter(router_) {}

  function swap(
      IERC20 tokenIn,
      IERC20 tokenOut,
      uint256 amountIn,
      bytes memory swapData
  ) external returns (uint256 tokenOutAmt) {
    tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
    return _swap(tokenIn, tokenOut, amountIn, swapData);
  }
}

contract ForkOdosTest is Test {
    address deployer = 0x451F52446EBD4376d4a05f4267eF1a03Acf1aAf4; // vm.randomAddress();

    DeployUtils.Res res;

    MarketConfig marketConfig;

    address sender = 0x451F52446EBD4376d4a05f4267eF1a03Acf1aAf4; // vm.randomAddress();
    address receiver = sender;

    address treasurer = vm.randomAddress();
    string testdata;
    ITermMaxRouter router;

    address weth9Addr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address weethAddr = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address ptWeethAddr = 0x6ee2b5E19ECBa773a352E5B21415Dc419A700d1d;
    address ptWeethMarketAddr = 0x7d372819240D14fB477f17b964f95F33BeB4c704; // 26 Dec 2024

    address pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    address uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address odosRouter = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    // UniswapV3Adapter uniswapAdapter;
    // PendleSwapV3Adapter pendleAdapter;
    OdosV2AdapterMock odosAdapter;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21633135);

        vm.startPrank(deployer);
        // uniswapAdapter = new UniswapV3Adapter(uniswapRouter);
        // pendleAdapter = new PendleSwapV3Adapter(pendleRouter);
        odosAdapter = new OdosV2AdapterMock(odosRouter);
        

        vm.stopPrank();
    }


    function testLeverageFromXtWithOdos() public {
        vm.startPrank(sender);
        console.log("sender", sender);
        // deal(weth9Addr, sender, 1000e18);
        uint256 tokenAmtIn = 51869222;
        address inputToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
        address outputToken = weth9Addr;

        IOdosRouterV2.swapTokenInfo memory swapTokenInfoParam = IOdosRouterV2.swapTokenInfo(
            address(inputToken),
            tokenAmtIn,
            address(0xc19C5B63705807079DbF6d54071F9113233283F5),
            address(outputToken),
            15615669300592542,
            15459512607586616,
            address(receiver)
        );
        address odosExecutor = 0xB28Ca7e465C452cE4252598e0Bc96Aeba553CF82;
        uint32 odosReferralCode = 0;
        bytes memory odosSwapData = abi.encode(
            abi.encode(
                swapTokenInfoParam,
                hex"01020500030102000203000a02030001000104010aff000000000000000000002a79a0e0c226a58eeb99c5704d72d49177cc7516c19c5b63705807079dbf6d54071f9113233283f5a0b86991c6218b36c1d19d4a2e9eb0ce3606eb487a5d3a9dcd33cb8d527f7b5f96eb4fef43d55636",
                odosExecutor,
                odosReferralCode
            )
        );
        IERC20(inputToken).approve(address(odosAdapter), tokenAmtIn);
        odosAdapter.swap(IERC20(inputToken), IERC20(outputToken), tokenAmtIn, odosSwapData);

        vm.stopPrank();
    }

}
