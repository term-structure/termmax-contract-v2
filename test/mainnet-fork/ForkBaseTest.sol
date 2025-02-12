pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "contracts/router/ITermMaxRouter.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {TermMaxOrder, OrderConfig} from "contracts/TermMaxOrder.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockOrder} from "contracts/test/MockOrder.sol";
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
import {JSONLoader} from "test/utils/JSONLoader.sol";
import "forge-std/Test.sol";

abstract contract ForkBaseTest is Test {

    string dataPath;

    string[] tokenPairs;

    function _finishSetup() internal virtual;

    function setUp() public {
        dataPath = _getDataPath();
        _readTokenPairs();

        uint256 mainnetFork = vm.createFork(_getForkRpcUrl());
        vm.selectFork(mainnetFork);

        _finishSetup();
    }

    function _getForkRpcUrl() internal view virtual returns (string memory);

    function _getDataPath() internal view virtual returns (string memory);

    function _readTokenPairs() internal{
        tokenPairs = vm.parseJsonStringArray(dataPath, ".tokenPairs");
    }

    function _readBlockNumber(string memory key) internal view returns (uint256){
        return uint256(vm.parseJsonUint(dataPath, string.concat(key, ".blockNumber")));
    }

    function _readMarketInitialParams(string memory key) internal returns (MarketInitialParams memory marketInitialParams){
        marketInitialParams.admin = vm.randomAddress();
        marketInitialParams.collateral = vm.parseJsonAddress(dataPath,string.concat(key, ".collateral"));
        marketInitialParams.debtToken = IERC20Metadata(vm.parseJsonAddress(dataPath,string.concat(key, ".debtToken")));

        marketInitialParams.tokenName = key;
        marketInitialParams.tokenSymbol = key;

        MarketConfig memory marketConfig;
        marketConfig.feeConfig.redeemFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.redeemFeeRatio"))));
        marketConfig.feeConfig.issueFtFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.issueFtFeeRatio"))));
        marketConfig.feeConfig.issueFtFeeRef =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.issueFtFeeRef"))));
        marketConfig.feeConfig.lendTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.lendTakerFeeRatio"))));
        marketConfig.feeConfig.borrowTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.borrowTakerFeeRatio"))));
        marketConfig.feeConfig.lendMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.lendMakerFeeRatio"))));
        marketConfig.feeConfig.borrowMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".feeConfig.borrowMakerFeeRatio"))));
        marketInitialParams.marketConfig = marketConfig;

        marketConfig.treasurer = vm.randomAddress();
        marketConfig.maturity = uint64(86400 * vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".duration"))));

        marketInitialParams.loanConfig.maxLtv =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".loanConfig.maxLtv"))));
        marketInitialParams.loanConfig.liquidationLtv =
            uint32(vm.parseUint(vm.parseJsonString(dataPath,string.concat(key, ".loanConfig.liquidationLtv"))));
        marketInitialParams.loanConfig.liquidatable =
            vm.parseBool(vm.parseJsonString(dataPath,string.concat(key, ".loanConfig.liquidatable")));

        marketInitialParams.gtInitalParams = abi.encode(type(uint256).max);
        
        return marketInitialParams;
    }

    function _readOrderConfig(string memory key) internal view returns (OrderConfig memory orderConfig) {
        orderConfig = JSONLoader.getOrderConfigFromJson(dataPath, key);
        return orderConfig;
    }

    function _readVaultInitialParams(address admin, IERC20 debtToken, string memory key) internal returns (VaultInitialParams memory vaultInitialParams){
        vaultInitialParams.admin = admin;
        vaultInitialParams.curator = vm.randomAddress();
        vaultInitialParams.timelock = 1 days;
        vaultInitialParams.asset = debtToken;
        vaultInitialParams.maxCapacity = type(uint128).max;
        vaultInitialParams.name = string.concat("Vault-", key);
        vaultInitialParams.symbol = string.concat("Vault-", key);
        vaultInitialParams.performanceFeeRate = 0.1e8;
        return vaultInitialParams;
    }

    function deployFactory(address admin) public returns (TermMaxFactory factory) {
        address tokenImplementation = address(new MintableERC20());
        address orderImplementation = address(new TermMaxOrder());
        TermMaxMarket m = new TermMaxMarket(tokenImplementation, orderImplementation);
        factory = new TermMaxFactory(admin, address(m));
    }

    function deployFactoryWithMockOrder(address admin) public returns (TermMaxFactory factory) {
        address tokenImplementation = address(new MintableERC20());
        address orderImplementation = address(new MockOrder());
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
