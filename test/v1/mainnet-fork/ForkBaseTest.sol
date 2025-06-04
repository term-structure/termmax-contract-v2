pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {TermMaxMarket, Constants, SafeCast} from "contracts/v1/TermMaxMarket.sol";
import {TermMaxOrder, OrderConfig} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockOrder} from "contracts/v1/test/MockOrder.sol";
import {IMintableERC20, MintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {SwapAdapter} from "contracts/v1/test/testnet/SwapAdapter.sol";
import {IOracle, OracleAggregator} from "contracts/v1/oracle/OracleAggregator.sol";
import {IOrderManager, OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {ITermMaxVault, TermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/v1/storage/TermMaxStorage.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import "forge-std/Test.sol";

abstract contract ForkBaseTest is Test {
    using SafeCast for *;

    string jsonData;

    string[] tokenPairs;

    function _finishSetup() internal virtual;

    function setUp() public {
        jsonData = vm.readFile(_getDataPath());
        _readTokenPairs();

        uint256 mainnetFork = vm.createFork(_getForkRpcUrl());
        vm.selectFork(mainnetFork);

        _finishSetup();
    }

    function _getForkRpcUrl() internal view virtual returns (string memory);

    function _getDataPath() internal view virtual returns (string memory);

    function _readTokenPairs() internal {
        // uint256 len = vm.parseJsonUint(jsonData, ".tokenPairs.length");
        string[] memory _tokenPairs = vm.parseJsonStringArray(jsonData, ".tokenPairs");
        for (uint256 i = 0; i < _tokenPairs.length; i++) {
            tokenPairs.push(string.concat(".", _tokenPairs[i]));
        }
    }

    function _readBlockNumber(string memory key) internal view returns (uint256) {
        return uint256(vm.parseJsonUint(jsonData, string.concat(key, ".blockNumber")));
    }

    function _readMarketInitialParams(string memory key)
        internal
        returns (MarketInitialParams memory marketInitialParams)
    {
        marketInitialParams.admin = vm.randomAddress();
        marketInitialParams.collateral = vm.parseJsonAddress(jsonData, string.concat(key, ".collateral"));
        marketInitialParams.debtToken = IERC20Metadata(vm.parseJsonAddress(jsonData, string.concat(key, ".debtToken")));

        marketInitialParams.tokenName = key;
        marketInitialParams.tokenSymbol = key;

        MarketConfig memory marketConfig;

        marketConfig.feeConfig.mintGtFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".feeConfig.mintGtFeeRatio"))));
        marketConfig.feeConfig.mintGtFeeRef =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".feeConfig.mintGtFeeRef"))));
        marketConfig.feeConfig.lendTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".feeConfig.lendTakerFeeRatio"))));
        marketConfig.feeConfig.borrowTakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".feeConfig.borrowTakerFeeRatio"))));
        marketConfig.feeConfig.lendMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".feeConfig.lendMakerFeeRatio"))));
        marketConfig.feeConfig.borrowMakerFeeRatio =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".feeConfig.borrowMakerFeeRatio"))));
        marketInitialParams.marketConfig = marketConfig;

        marketConfig.treasurer = vm.randomAddress();
        marketConfig.maturity =
            uint64(86400 * vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".duration"))));

        marketInitialParams.loanConfig.maxLtv =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".loanConfig.maxLtv"))));
        marketInitialParams.loanConfig.liquidationLtv =
            uint32(vm.parseUint(vm.parseJsonString(jsonData, string.concat(key, ".loanConfig.liquidationLtv"))));
        marketInitialParams.loanConfig.liquidatable =
            vm.parseBool(vm.parseJsonString(jsonData, string.concat(key, ".loanConfig.liquidatable")));

        marketInitialParams.gtInitalParams = abi.encode(type(uint256).max);

        return marketInitialParams;
    }

    function _readOrderConfig(string memory key) internal view returns (OrderConfig memory orderConfig) {
        orderConfig = JSONLoader.getOrderConfigFromJson(jsonData, string.concat(key, ".orderConfig"));
        return orderConfig;
    }

    function _readVaultInitialParams(address admin, IERC20 debtToken, string memory key)
        internal
        returns (VaultInitialParams memory vaultInitialParams)
    {
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

    function _setPriceFeedInTokenDecimal8(
        MockPriceFeed priceFeed,
        uint8 tokenDecimals,
        MockPriceFeed.RoundData memory roundData
    ) internal {
        roundData.answer =
            (roundData.answer.toUint256() * (10 ** uint256(tokenDecimals)) / Constants.DECIMAL_BASE).toInt256();
        priceFeed.updateRoundData(roundData);
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
        oracle = new OracleAggregator(admin, 0);
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
