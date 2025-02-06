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
import {IFlashLoanReceiver} from "contracts/IFlashLoanReceiver.sol";
import {ITermMaxMarket, TermMaxMarket, Constants, MarketEvents, MarketErrors} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder, TermMaxOrder, ISwapCallback, OrderEvents, OrderErrors} from "contracts/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultErrors, VaultEvents, ITermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {OrderManager} from "contracts/vault/OrderManager.sol";
import {VaultConstants} from "contracts/lib/VaultConstants.sol";
import {PendingAddress, PendingUint192} from "contracts/lib/PendingLib.sol";
import {MockSwapAdapter} from "contracts/test/MockSwapAdapter.sol";
import {SwapUnit, ISwapAdapter} from "contracts/router/ISwapAdapter.sol";
import {RouterErrors, RouterEvents, TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import "contracts/storage/TermMaxStorage.sol";

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

    uint timelock = 86400;
    uint maxCapacity = 1000000e18;
    uint64 performanceFeeRate = 0.5e8;

    ITermMaxMarket market2;

    uint currentTime;
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
        res.collateralOracle.updateRoundData(
            JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.eth")
        );
        res.debtOracle.updateRoundData(JSONLoader.getRoundDataFromJson(testdata, ".priceData.ETH_2000_DAI_1.dai"));

        uint amount = 10000e8;

        initialParams = VaultInitialParams(
            admin,
            curator,
            timelock,
            res.debt,
            maxCapacity,
            "Vault-DAI",
            "Vault-DAI",
            performanceFeeRate
        );

        res.vault = DeployUtils.deployVault(initialParams);

        res.vault.submitGuardian(guardian);
        res.vault.setIsAllocator(allocator, true);

        res.vault.submitMarket(address(res.market), true);
        vm.warp(currentTime + timelock + 1);
        res.vault.acceptMarket(address(res.market));
        vm.warp(currentTime);

        res.debt.mint(admin, amount);
        res.debt.approve(address(res.vault), amount);
        res.vault.deposit(amount, admin);

        res.order = res.vault.createOrder(res.market, maxCapacity, amount, orderConfig.curveCuts);

        res.router = DeployUtils.deployRouter(admin);
        res.router.setMarketWhitelist(address(res.market), true);
        adapter = new MockSwapAdapter(pool);

        res.router.setAdapterWhitelist(address(adapter), true);
        vm.stopPrank();
    }
}
