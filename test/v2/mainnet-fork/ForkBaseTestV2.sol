pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactoryV2, ITermMaxFactory} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {ITermMaxRouterV2, TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {TermMaxMarketV2, Constants, SafeCast} from "contracts/v2/TermMaxMarketV2.sol";
import {TermMaxOrderV2, OrderConfig} from "contracts/v2/TermMaxOrderV2.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockOrderV2} from "contracts/v2/test/MockOrderV2.sol";
import {MintableERC20V2} from "contracts/v2/tokens/MintableERC20V2.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {SwapAdapter} from "contracts/v1/test/testnet/SwapAdapter.sol";
import {IOracleV2, OracleAggregatorV2} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOrderManager, OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {ITermMaxVaultV2, TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {ITermMaxVault} from "contracts/v1/vault/ITermMaxVault.sol";
import {OrderManagerV2} from "contracts/v2/vault/OrderManagerV2.sol";
import {TermMaxVaultFactoryV2} from "contracts/v2/factory/TermMaxVaultFactoryV2.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/v1/storage/TermMaxStorage.sol";
import {JSONLoader} from "../utils/JSONLoader.sol";
import "forge-std/Test.sol";

abstract contract ForkBaseTestV2 is Test {
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

    function deployFactory(address admin) public returns (TermMaxFactoryV2 factory) {
        address tokenImplementation = address(new MintableERC20V2());
        address orderImplementation = address(new TermMaxOrderV2());
        TermMaxMarketV2 m = new TermMaxMarketV2(tokenImplementation, orderImplementation);
        factory = new TermMaxFactoryV2(admin, address(m));
    }

    function deployFactoryWithMockOrder(address admin) public returns (TermMaxFactoryV2 factory) {
        address tokenImplementation = address(new MintableERC20V2());
        address orderImplementation = address(new MockOrderV2());
        TermMaxMarketV2 m = new TermMaxMarketV2(tokenImplementation, orderImplementation);
        factory = new TermMaxFactoryV2(admin, address(m));
    }

    function deployVaultFactory() public returns (TermMaxVaultFactoryV2 vaultFactory) {
        OrderManagerV2 orderManager = new OrderManagerV2();
        TermMaxVaultV2 implementation = new TermMaxVaultV2(address(orderManager));
        vaultFactory = new TermMaxVaultFactoryV2(address(implementation));
    }

    function deployOracleAggregator(address admin) public returns (OracleAggregatorV2 oracle) {
        oracle = new OracleAggregatorV2(admin, 0);
    }

    function deployMockPriceFeed(address admin) public returns (MockPriceFeed priceFeed) {
        priceFeed = new MockPriceFeed(admin);
    }

    function deployRouter(address admin) public returns (TermMaxRouterV2 router) {
        TermMaxRouterV2 implementation = new TermMaxRouterV2();
        bytes memory data = abi.encodeCall(TermMaxRouterV2.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouterV2(address(proxy));
    }
}
