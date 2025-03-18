// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {MarketViewer} from "contracts/router/MarketViewer.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {TermMaxMarket, IGearingToken} from "contracts/TermMaxMarket.sol";
import {TermMaxOrder} from "contracts/TermMaxOrder.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IMintableERC20, MintableERC20} from "contracts/tokens/MintableERC20.sol";
import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";
import {JSONLoader} from "test/utils/JSONLoader.sol";
import {FaucetERC20} from "contracts/test/testnet/FaucetERC20.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import {IOrderManager, OrderManager} from "contracts/vault/OrderManager.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";
import {
    MarketConfig,
    GtConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/storage/TermMaxStorage.sol";
import {KyberswapV2Adapter} from "contracts/router/swapAdapters/KyberswapV2Adapter.sol";
import {OdosV2Adapter} from "contracts/router/swapAdapters/OdosV2Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {UniswapV3Adapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {MockAave, IFlashLoanAave} from "contracts/test/MockAave.sol";
import {MockMorpho, IFlashLoanMorpho} from "contracts/test/MockMorpho.sol";
import {LiquidationBot} from "contracts/extensions/LiquidationBot.sol";
import {MockSwapAdapter} from "contracts/test/MockSwapAdapter.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";

contract LiquidationTest is Script {
    // deployer config
    uint256 liquidatorPrivateKey = vm.envUint("LIQUIDATOR_PRIVATE_KEY");
    address liquidatorAddr = vm.addr(liquidatorPrivateKey);

    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);

    uint256 priceFeedAdminPrivateKey = vm.envUint("PRICE_FEED_ADMIN_PRIVATE_KEY");

    function run() public {
        MockERC20 collateralToken = MockERC20(0x254310e0929A2695ad54E67B982E793537D792BD);
        MockERC20 debtToken = MockERC20(0x3062e1Fe103b3b6D0F09fBd314c2c66835483DBe);

        IGearingToken gt = IGearingToken(0x9063bDD6b6305C4ffe79b157a18FAfA923dA0361);
        GtConfig memory gtConfig = gt.getGtConfig();
        IOracle oracle = gtConfig.loanConfig.oracle;
        console.log("maxLtv",gtConfig.loanConfig.maxLtv);
        console.log("lltv",gtConfig.loanConfig.liquidationLtv);
        TermMaxMarket market = TermMaxMarket(0x4aa8F4396cc0D457aaE55f57570c4A8C6D35b08C);
        console.log("market", address(market));
        MockPriceFeed collateralPriceFeed = MockPriceFeed(0xD3217Bc65fA095737661734A3C776B7DfFBda68A);
        (uint256 ac, uint8 dc) = oracle.getPrice(address(collateralToken));
        console.log("collateralPrice", ac);
        console.log("dc", dc);
        MockPriceFeed debtPriceFeed = MockPriceFeed(0x09cc79C71BF57Dca31217669e9145dcccea3fbC6);
        (uint256 ad, uint8 dd) = oracle.getPrice(address(debtToken));
        console.log("debtPrice", ad);
        console.log("dd", dd);

        console.log("price feeds owner", debtPriceFeed.owner());

        vm.startBroadcast(liquidatorPrivateKey);
        // debtToken.approve(address(gt), type(uint128).max);
        gt.liquidate(2, 287705886, true);

        // gt.liquidate(2, 576e6, true);

        vm.stopBroadcast();

        // vm.startBroadcast(deployerPrivateKey);

        // market.issueFt(deployerAddr, 576e6, abi.encode(0.2e18));

        // market.issueFt(deployerAddr, 2880e6, abi.encode(1e18));

        // vm.stopBroadcast();

        // vm.startBroadcast(priceFeedAdminPrivateKey);

        // console.log("price feeds updated");
        // MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
        //     roundId: 2,
        //     answer: int256(3200e8),
        //     startedAt: block.timestamp,
        //     updatedAt: block.timestamp,
        //     answeredInRound: 0
        // });
        // collateralPriceFeed.updateRoundData(roundData);
        // vm.stopBroadcast();

        // console.log("price feeds updated");
        // MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
        //     roundId: 1,
        //     answer: int256(2000e8),
        //     startedAt: block.timestamp,
        //     updatedAt: block.timestamp,
        //     answeredInRound: 0
        // });
        // collateralPriceFeed.updateRoundData(roundData);

        // roundData.answer = int256(1e8);
        // debtPriceFeed.updateRoundData(roundData);

        // MockAave mockAave = new MockAave();
        // console.log("mockAave", address(mockAave));

        // MockMorpho mockMorpho = new MockMorpho();
        // console.log("mockMorpho", address(mockMorpho));

        // address aaveAddressesProvider = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
        // LiquidationBot liquidationBot = new LiquidationBot(
        //     IFlashLoanAave(address(mockAave)), aaveAddressesProvider, IFlashLoanMorpho(address(mockMorpho))
        // );
        // console.log("liquidationBot", address(liquidationBot));

        // {
        //     console.log("issue Ft");
        //     TermMaxMarket(market).issueFt(deployerAddr, 90e8, abi.encode(0.1e18));

        //     console.log("update collateral price");
        //     roundData.answer = int256(1000e8);
        //     collateralPriceFeed.updateRoundData(roundData);

        //     LiquidationBot liquidationBot = LiquidationBot(0x240a0AaBD89717bEc6F0EE928E08A573Ba0D4429);
        //     uint256 gtId = 2;
        //     (bool isLiquidable, uint128 maxRepayAmt, uint256 cToLiquidator, uint256 incomeValue) =
        //         liquidationBot.simulateLiquidation(gt, gtId);
        //     console.log("isLiquidable", isLiquidable);
        //     console.log("maxRepayAmt", maxRepayAmt);
        //     console.log("cToLiquidator", cToLiquidator);
        //     console.log("incomeValue", incomeValue);
        // }


        // // deploy contracts
        // vm.startBroadcast(liquidatorPrivateKey);

        // debtToken.mint(liquidatorAddr, 100000e8);
        // debtToken.approve(address(gt), type(uint128).max);
        // uint256 gtId = 1;
        // gt.liquidate(gtId, 100e8, true);

        // vm.stopBroadcast();
    }
}
