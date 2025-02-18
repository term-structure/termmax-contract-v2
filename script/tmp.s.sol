// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {TermMaxFactory} from "../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "../contracts/router/ITermMaxRouter.sol";
import {ISwapCallback, TermMaxOrder} from "../contracts/TermMaxOrder.sol";
import {ITermMaxOrder} from "../contracts/TermMaxOrder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket, Constants} from "../contracts/TermMaxMarket.sol";
import {ITermMaxMarket} from "../contracts/TermMaxMarket.sol";
import {MockERC20} from "../contracts/test/MockERC20.sol";
import {MarketConfig, CurveCuts, CurveCut} from "../contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "../contracts/tokens/IGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../contracts/test/MockSwapAdapter.sol";
import {Faucet} from "../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../contracts/test/testnet/FaucetERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {SwapUnit} from "../contracts/router/ISwapAdapter.sol";
import {MarketConfig} from "../contracts/storage/TermMaxStorage.sol";

contract E2ETest is Script {
    // address config
    address faucetAddr = address(0xb927B74d5D9c3985D4DCdd62CbffEc66CF527fAa);
    address routerAddr = address(0xbFccC3c7F739d4aE7CCf680b3fafcFB5Bdc4f842);
    address swapAdapter = address(0xC622E39c594570c731baCcDc2b6cD062EF941b06);
    address marketAddr = address(0xD0586B5a5F97347C769983C404348346FE26f38e);
    address orderAddr = address(0x550a95c76A929635E7836cBef401C378485f4422);

    Faucet faucet = Faucet(faucetAddr);
    TermMaxRouter router = TermMaxRouter(routerAddr);
    TermMaxMarket market = TermMaxMarket(marketAddr);
    TermMaxOrder order = TermMaxOrder(orderAddr);
    IMintableERC20 ft;
    IMintableERC20 xt;
    IGearingToken gt;
    address collateralAddr;
    IERC20 underlyingERC20;
    FaucetERC20 collateral;
    FaucetERC20 underlying;
    address collateralPriceFeedAddr;
    address underlyingPriceFeedAddr;

    function run() public {
        vm.startBroadcast();

        // 建立 lendCurveCuts 陣列
        CurveCut[] memory lendCuts = new CurveCut[](4);
        lendCuts[0] = CurveCut(0, 6275293736195044195434496, 3734313483298);
        lendCuts[1] = CurveCut(500000000000, 17140502907442753248952320, 6498061538208);
        lendCuts[2] = CurveCut(3000000000000, 2847642655783149872611328, 871381198827);
        lendCuts[3] = CurveCut(3900000000000, 2847642655783149872611328, 871381198827);

        // 建立 borrowCurveCuts 陣列
        CurveCut[] memory borrowCuts = new CurveCut[](4);
        borrowCuts[0] = CurveCut(0, 3209532558827220228898816, 2832637110862);
        borrowCuts[1] = CurveCut(898879919000, 16075261900017108000964608, 7452217729400);
        borrowCuts[2] = CurveCut(2900000000000, 2969697082335298089648128, 1549492085426);
        borrowCuts[3] = CurveCut(3900000000000, 2969697082335298089648128, 1549492085426);

        // 宣告 CurveCuts 結構
        CurveCuts memory cuts = CurveCuts({lendCurveCuts: lendCuts, borrowCurveCuts: borrowCuts});

        ISwapCallback swapTrigger = ISwapCallback(address(0));
        router.createOrderAndDeposit(
            market,
            address(0x9b1A93b6C9F275FE1720e18331315Ec35484a662),
            3900000000000,
            swapTrigger,
            10000000000,
            0,
            0,
            cuts
        );
        vm.stopBroadcast();
    }
}
