pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {TermMaxOrder} from "contracts/TermMaxOrder.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IMintableERC20, MintableERC20} from "contracts/tokens/MintableERC20.sol";
import {SwapAdapter} from "contracts/test/testnet/SwapAdapter.sol";
import {IOracle, OracleAggregator} from "contracts/oracle/OracleAggregator.sol";
import {IOrderManager, OrderManager} from "contracts/vault/OrderManager.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/factory/VaultFactory.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/storage/TermMaxStorage.sol";
import {EnvConfig} from "test/mainnet-fork/EnvConfig.sol";
import "forge-std/Test.sol";

abstract contract ForkBaseTest is Test {
    function setUp() public {
        EnvConfig memory env = _getEnv();
        if (env.forkBlockNumber > 0) {
            uint256 mainnetFork = vm.createFork(env.forkRpcUrl);
            vm.selectFork(mainnetFork);
            vm.rollFork(env.forkBlockNumber);
        }
        _initialize(env.extraData);
        _finishSetup();
    }

    function _initialize(bytes memory data) internal virtual;

    function _finishSetup() internal virtual;

    function _getEnv() internal virtual returns (EnvConfig memory env);

    function deployFactory(address admin) public returns (TermMaxFactory factory) {
        address tokenImplementation = address(new MintableERC20());
        address orderImplementation = address(new TermMaxOrder());
        TermMaxMarket m = new TermMaxMarket(tokenImplementation, orderImplementation);
        factory = new TermMaxFactory(admin, address(m));
    }

    function deployVaultFactory() public returns (VaultFactory vaultFactory) {
        OrderManager orderManager = new OrderManager();
        TermMaxVault implementation = new TermMaxVault(address(orderManager));
        vaultFactory = new VaultFactory(address(implementation));
    }

    function deployOracleAggregator(address admin) public returns (OracleAggregator oracle) {
        OracleAggregator implementation = new OracleAggregator();
        bytes memory data = abi.encodeCall(OracleAggregator.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        oracle = OracleAggregator(address(proxy));
    }

    function deployMockPriceFeed(address admin) public returns (MockPriceFeed priceFeed) {
        priceFeed = new MockPriceFeed(admin);
    }

    function deployRouter(address admin) public returns (TermMaxRouter router) {
        TermMaxRouter implementation = new TermMaxRouter();
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouter(address(proxy));
    }
}
