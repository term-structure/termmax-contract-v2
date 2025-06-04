// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {JSONLoader} from "./utils/JSONLoader.sol";
import {StateChecker} from "./utils/StateChecker.sol";
import {SwapUtils} from "./utils/SwapUtils.sol";
import {LoanUtils} from "./utils/LoanUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFlashLoanReceiver} from "contracts/v1/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/v1/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents, OrderErrors} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {VaultErrors, VaultEvents, ITermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {VaultConstants} from "contracts/v1/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/v1/lib/PendingLib.sol";
import {MockSwapAdapter} from "contracts/v1/test/MockSwapAdapter.sol";
import {SwapUnit, ISwapAdapter} from "contracts/v1/router/ISwapAdapter.sol";
import {RouterErrors, RouterEvents, TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

abstract contract TermMaxTestBase is Test {
    using JSONLoader for *;
    using SafeCast for *;

    DeployUtils.Res res;

    OrderConfig orderConfig;
    MarketConfig marketConfig;

    address admin = vm.randomAddress();
    address curator = vm.randomAddress();
    address allocator = vm.randomAddress();
    address guardian = vm.randomAddress();
    address treasurer = vm.randomAddress();
    string testdata;

    ITermMaxVault vault;

    uint256 timelock = 86400;
    uint256 maxCapacity = 1000000e18;
    uint64 performanceFeeRate = 0.5e8;

    ITermMaxMarket market2;

    uint256 currentTime;
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;
    VaultInitialParams initialParams;

    address pool = vm.randomAddress();

    MockSwapAdapter adapter;

    function setUp() public {
        vm.startPrank(admin);
        testdata = vm.readFile(string.concat(vm.projectRoot(), "/test/testdata/testdata.json"));

        currentTime = vm.parseUint(vm.parseJsonString(testdata, ".currentTime"));
        vm.warp(currentTime);

        marketConfig = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        orderConfig = JSONLoader.getOrderConfigFromJson(testdata, ".orderConfig");
        marketConfig.maturity = uint64(currentTime + 90 days);
        res = DeployUtils.deployMockMarket(admin, marketConfig, maxLtv, liquidationLtv);
        MarketConfig memory marketConfig2 = JSONLoader.getMarketConfigFromJson(treasurer, testdata, ".marketConfig");
        marketConfig2.maturity = uint64(currentTime + 180 days);

        market2 = ITermMaxMarket(
            res.factory.createMarket(
                DeployUtils.GT_ERC20,
                MarketInitialParams({
                    collateral: address(res.collateral),
                    debtToken: res.debt,
                    admin: admin,
                    gtImplementation: address(0),
                    marketConfig: marketConfig2,
                    loanConfig: LoanConfig({
                        maxLtv: maxLtv,
                        liquidationLtv: liquidationLtv,
                        liquidatable: true,
                        oracle: res.oracle
                    }),
                    gtInitalParams: abi.encode(type(uint256).max),
                    tokenName: "test",
                    tokenSymbol: "test"
                }),
                0
            )
        );

        // update oracle
        res.collateralOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth"));
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        initialParams = VaultInitialParams(
            admin, curator, timelock, res.debt, maxCapacity, "Vault-DAI", "Vault-DAI", performanceFeeRate
        );

        res.vault = DeployUtils.deployVault(initialParams);

        res.vault.submitGuardian(guardian);
        res.vault.setIsAllocator(allocator, true);

        res.vault.submitMarket(address(res.market), true);
        vm.warp(currentTime + timelock + 1);
        res.vault.acceptMarket(address(res.market));
        vm.warp(currentTime);

        res.order = res.vault.createOrder(res.market, maxCapacity, 0, orderConfig.curveCuts);

        res.router = DeployUtils.deployRouter(admin);
        adapter = new MockSwapAdapter(pool);
        res.router.setAdapterWhitelist(address(adapter), true);
        vm.stopPrank();
    }
}
