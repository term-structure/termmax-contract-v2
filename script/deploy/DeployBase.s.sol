// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/v1/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {MarketViewer} from "contracts/v1/router/MarketViewer.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {TermMaxMarket} from "contracts/v1/TermMaxMarket.sol";
import {TermMaxOrder} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20, MintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {SwapAdapter} from "contracts/v1/test/testnet/SwapAdapter.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {FaucetERC20} from "contracts/v1/test/testnet/FaucetERC20.sol";
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
import {ERC4626VaultAdapterV2} from "contracts/v1/router/specAdapters/ERC4626VaultAdapterV2.sol";
import {OdosV2AdapterV2} from "contracts/v1/router/specAdapters/OdosV2AdapterV2.sol";
import {PendleSwapV3AdapterV2} from "contracts/v1/router/specAdapters/PendleSwapV3AdapterV2.sol";
import {UniswapV3AdapterV2} from "contracts/v1/router/specAdapters/UniswapV3AdapterV2.sol";
import {ERC4626VaultAdapter} from "contracts/v1/router/swapAdapters/ERC4626VaultAdapter.sol";
import {OdosV2Adapter} from "contracts/v1/router/swapAdapters/OdosV2Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/v1/router/swapAdapters/PendleSwapV3Adapter.sol";
import {UniswapV3Adapter} from "contracts/v1/router/swapAdapters/UniswapV3Adapter.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessManager} from "contracts/v1/access/AccessManager.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract DeployBase is Script {
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

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

    function deployOracleAggregator(address admin, uint256 timelock) public returns (OracleAggregator oracle) {
        oracle = new OracleAggregator(admin, timelock);
    }

    function deployRouter(address admin) public returns (TermMaxRouter router) {
        TermMaxRouter implementation = new TermMaxRouter();
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouter(address(proxy));
    }

    function deployAccessManager(address admin) public returns (AccessManager accessManager) {
        AccessManager implementation = new AccessManager();
        bytes memory data = abi.encodeCall(AccessManager.initialize, admin);
        address proxy = address(new ERC1967Proxy(address(implementation), data));

        accessManager = AccessManager(proxy);
    }

    function deployCore(address deployerAddr, address accessManagerAddr, uint256 oracleTimelock)
        public
        returns (
            TermMaxFactory factory,
            VaultFactory vaultFactory,
            OracleAggregator oracleAggregator,
            TermMaxRouter router,
            SwapAdapter swapAdapter,
            Faucet faucet,
            MarketViewer marketViewer
        )
    {
        // deploy access manager
        AccessManager accessManager = AccessManager(accessManagerAddr);

        // deploy factory
        factory = deployFactory(address(accessManager));

        // deploy vault factory
        vaultFactory = deployVaultFactory();

        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(address(accessManager), oracleTimelock);

        // deploy router
        router = deployRouter(address(accessManager));

        // deploy swap adapter
        swapAdapter = new SwapAdapter(deployerAddr);
        accessManager.setAdapterWhitelist(router, address(swapAdapter), true);

        // deploy faucet
        faucet = new Faucet(deployerAddr);

        // deploy market viewer
        marketViewer = deployMarketViewer();
    }

    function deployCoreMainnet(
        address accessManagerAddr,
        address uniswapV3Router,
        address odosV2Router,
        address pendleSwapV3Router,
        uint256 oracleTimelock
    )
        public
        returns (
            TermMaxFactory factory,
            VaultFactory vaultFactory,
            OracleAggregator oracleAggregator,
            TermMaxRouter router,
            MarketViewer marketViewer,
            UniswapV3Adapter uniswapV3Adapter,
            OdosV2Adapter odosV2Adapter,
            PendleSwapV3Adapter pendleSwapV3Adapter,
            ERC4626VaultAdapter vaultAdapter
        )
    {
        // deploy access manager
        AccessManager accessManager = AccessManager(accessManagerAddr);

        // deploy factory
        factory = deployFactory(address(accessManager));

        // deploy vault factory
        vaultFactory = deployVaultFactory();

        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(address(accessManager), oracleTimelock);

        // deploy router
        router = deployRouter(address(accessManager));

        // deploy market viewer
        marketViewer = deployMarketViewer();

        // deploy and whitelist swap adapter
        uniswapV3Adapter = new UniswapV3Adapter(address(uniswapV3Router));
        odosV2Adapter = new OdosV2Adapter(odosV2Router);
        pendleSwapV3Adapter = new PendleSwapV3Adapter(address(pendleSwapV3Router));
        vaultAdapter = new ERC4626VaultAdapter();

        accessManager.setAdapterWhitelist(router, address(uniswapV3Adapter), true);
        accessManager.setAdapterWhitelist(router, address(odosV2Adapter), true);
        accessManager.setAdapterWhitelist(router, address(pendleSwapV3Adapter), true);
        accessManager.setAdapterWhitelist(router, address(vaultAdapter), true);
    }

    function deployAdapters(
        address accessManagerAddr,
        address routerAddr,
        address uniswapV3Router,
        address odosV2Router,
        address pendleSwapV3Router
    )
        public
        returns (
            UniswapV3AdapterV2 uniswapV3Adapter,
            OdosV2AdapterV2 odosV2Adapter,
            PendleSwapV3AdapterV2 pendleSwapV3Adapter,
            ERC4626VaultAdapterV2 vaultAdapter
        )
    {
        // deploy access manager
        AccessManager accessManager = AccessManager(accessManagerAddr);

        // deploy router
        TermMaxRouter router = TermMaxRouter(routerAddr);

        // deploy and whitelist swap adapter
        uniswapV3Adapter = new UniswapV3AdapterV2(address(uniswapV3Router));
        odosV2Adapter = new OdosV2AdapterV2(odosV2Router);
        pendleSwapV3Adapter = new PendleSwapV3AdapterV2(address(pendleSwapV3Router));
        vaultAdapter = new ERC4626VaultAdapterV2();

        accessManager.setAdapterWhitelist(router, address(uniswapV3Adapter), true);
        accessManager.setAdapterWhitelist(router, address(odosV2Adapter), true);
        accessManager.setAdapterWhitelist(router, address(pendleSwapV3Adapter), true);
        accessManager.setAdapterWhitelist(router, address(vaultAdapter), true);
    }

    function deployMarkets(
        address accessManagerAddr,
        address factoryAddr,
        address oracleAddr,
        address faucetAddr,
        string memory deployDataPath,
        address treasurerAddr,
        address priceFeedOperatorAddr
    ) public returns (TermMaxMarket[] memory markets, JsonLoader.Config[] memory configs) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        AccessManager accessManager = AccessManager(accessManagerAddr);
        IOracle oracle = IOracle(oracleAddr);
        Faucet faucet = Faucet(faucetAddr);

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        markets = new TermMaxMarket[](configs.length);

        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            // deploy underlying & collateral
            bytes32 tokenKey = faucet.calcTokenKey(
                config.collateralConfig.name, config.collateralConfig.symbol, config.collateralConfig.decimals
            );
            uint256 tokenId = faucet.getTokenIdByKey(tokenKey);
            FaucetERC20 collateral;
            MockPriceFeed collateralPriceFeed;
            FaucetERC20 underlying;
            MockPriceFeed underlyingPriceFeed;
            if (tokenId == 0) {
                (collateral, collateralPriceFeed) = faucet.addToken(
                    config.collateralConfig.name, config.collateralConfig.symbol, config.collateralConfig.decimals
                );

                collateralPriceFeed.updateRoundData(
                    MockPriceFeed.RoundData({
                        roundId: 1,
                        answer: config.collateralConfig.initialPrice,
                        startedAt: block.timestamp,
                        updatedAt: block.timestamp,
                        answeredInRound: 1
                    })
                );
                collateralPriceFeed.transferOwnership(priceFeedOperatorAddr);

                accessManager.submitPendingOracle(
                    oracle,
                    address(collateral),
                    IOracle.Oracle(collateralPriceFeed, collateralPriceFeed, uint32(365 days))
                );
                accessManager.acceptPendingOracle(oracle, address(collateral));
            } else {
                collateral = FaucetERC20(faucet.getTokenConfig(tokenId).tokenAddr);
                collateralPriceFeed = MockPriceFeed(faucet.getTokenConfig(tokenId).priceFeedAddr);
            }

            tokenKey = faucet.calcTokenKey(
                config.underlyingConfig.name, config.underlyingConfig.symbol, config.underlyingConfig.decimals
            );
            tokenId = faucet.getTokenIdByKey(tokenKey);
            if (tokenId == 0) {
                (underlying, underlyingPriceFeed) = faucet.addToken(
                    config.underlyingConfig.name, config.underlyingConfig.symbol, config.underlyingConfig.decimals
                );

                underlyingPriceFeed.updateRoundData(
                    MockPriceFeed.RoundData({
                        roundId: 1,
                        answer: config.underlyingConfig.initialPrice,
                        startedAt: block.timestamp,
                        updatedAt: block.timestamp,
                        answeredInRound: 1
                    })
                );
                underlyingPriceFeed.transferOwnership(priceFeedOperatorAddr);
                accessManager.submitPendingOracle(
                    oracle,
                    address(underlying),
                    IOracle.Oracle(underlyingPriceFeed, underlyingPriceFeed, uint32(365 days))
                );
                accessManager.acceptPendingOracle(oracle, address(underlying));
            } else {
                underlying = FaucetERC20(faucet.getTokenConfig(tokenId).tokenAddr);
                underlyingPriceFeed = MockPriceFeed(faucet.getTokenConfig(tokenId).priceFeedAddr);
            }

            MarketConfig memory marketConfig = MarketConfig({
                treasurer: treasurerAddr,
                maturity: config.marketConfig.maturity,
                feeConfig: FeeConfig({
                    lendTakerFeeRatio: config.marketConfig.feeConfig.lendTakerFeeRatio,
                    lendMakerFeeRatio: config.marketConfig.feeConfig.lendMakerFeeRatio,
                    borrowTakerFeeRatio: config.marketConfig.feeConfig.borrowTakerFeeRatio,
                    borrowMakerFeeRatio: config.marketConfig.feeConfig.borrowMakerFeeRatio,
                    mintGtFeeRatio: config.marketConfig.feeConfig.mintGtFeeRatio,
                    mintGtFeeRef: config.marketConfig.feeConfig.mintGtFeeRef
                })
            });

            // deploy market
            MarketInitialParams memory initialParams = MarketInitialParams({
                collateral: address(collateral),
                debtToken: IERC20Metadata(address(underlying)),
                admin: accessManagerAddr,
                gtImplementation: address(0),
                marketConfig: marketConfig,
                loanConfig: LoanConfig({
                    oracle: oracle,
                    liquidationLtv: config.loanConfig.liquidationLtv,
                    maxLtv: config.loanConfig.maxLtv,
                    liquidatable: config.loanConfig.liquidatable
                }),
                gtInitalParams: abi.encode(type(uint256).max),
                tokenName: config.marketName,
                tokenSymbol: config.marketSymbol
            });

            TermMaxMarket market =
                TermMaxMarket(accessManager.createMarket(factory, GT_ERC20, initialParams, config.salt));
            markets[i] = market;
        }
    }

    function deployMarketsMainnet(
        address accessManagerAddr,
        address factoryAddr,
        address oracleAddr,
        string memory deployDataPath,
        address treasurerAddr
    ) public returns (TermMaxMarket[] memory markets, JsonLoader.Config[] memory configs) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        OracleAggregator oracle = OracleAggregator(oracleAddr);

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        markets = new TermMaxMarket[](configs.length);

        for (uint256 i; i < configs.length; i++) {
            JsonLoader.Config memory config = configs[i];

            MarketConfig memory marketConfig = MarketConfig({
                treasurer: treasurerAddr,
                maturity: config.marketConfig.maturity,
                feeConfig: FeeConfig({
                    lendTakerFeeRatio: config.marketConfig.feeConfig.lendTakerFeeRatio,
                    lendMakerFeeRatio: config.marketConfig.feeConfig.lendMakerFeeRatio,
                    borrowTakerFeeRatio: config.marketConfig.feeConfig.borrowTakerFeeRatio,
                    borrowMakerFeeRatio: config.marketConfig.feeConfig.borrowMakerFeeRatio,
                    mintGtFeeRatio: config.marketConfig.feeConfig.mintGtFeeRatio,
                    mintGtFeeRef: config.marketConfig.feeConfig.mintGtFeeRef
                })
            });

            // deploy market
            MarketInitialParams memory initialParams = MarketInitialParams({
                collateral: config.collateralConfig.tokenAddr,
                debtToken: IERC20Metadata(config.underlyingConfig.tokenAddr),
                admin: accessManagerAddr,
                gtImplementation: address(0),
                marketConfig: marketConfig,
                loanConfig: LoanConfig({
                    oracle: oracle,
                    liquidationLtv: config.loanConfig.liquidationLtv,
                    maxLtv: config.loanConfig.maxLtv,
                    liquidatable: config.loanConfig.liquidatable
                }),
                gtInitalParams: abi.encode(config.collateralCapForGt),
                tokenName: config.marketName,
                tokenSymbol: config.marketSymbol
            });
            AccessManager accessManager = AccessManager(accessManagerAddr);
            TermMaxMarket market =
                TermMaxMarket(accessManager.createMarket(factory, GT_ERC20, initialParams, config.salt));
            markets[i] = market;
        }
    }

    function deployVault(
        address factoryAddr,
        address accessManagerAddr,
        address curator,
        uint256 timelock,
        address assetAddr,
        uint256 maxCapacity,
        string memory name,
        string memory symbol,
        uint64 performanceFeeRate
    ) public returns (TermMaxVault vault) {
        VaultFactory vaultFactory = VaultFactory(factoryAddr);
        VaultInitialParams memory initialParams = VaultInitialParams({
            admin: accessManagerAddr,
            curator: curator,
            timelock: timelock,
            asset: IERC20(assetAddr),
            maxCapacity: maxCapacity,
            name: name,
            symbol: symbol,
            performanceFeeRate: performanceFeeRate
        });
        vault = TermMaxVault(vaultFactory.createVault(initialParams, 0));
    }

    function deployMarketViewer() public returns (MarketViewer marketViewer) {
        marketViewer = new MarketViewer();
    }

    function getGitCommitHash() public returns (bytes memory) {
        string[] memory inputs = new string[](3);
        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "HEAD";
        bytes memory result = vm.ffi(inputs);
        return result;
    }

    function getGitBranch() public returns (string memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "git";
        inputs[1] = "rev-parse";
        inputs[2] = "--abbrev-ref";
        inputs[3] = "HEAD";
        bytes memory result = vm.ffi(inputs);
        return string(result);
    }

    // Helper function to convert string to uppercase
    function toUpper(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bUpper = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            // Convert hyphen to underscore
            if (bStr[i] == 0x2D) {
                bUpper[i] = 0x5F; // '_'
                continue;
            }
            // Convert lowercase to uppercase
            if ((uint8(bStr[i]) >= 97) && (uint8(bStr[i]) <= 122)) {
                bUpper[i] = bytes1(uint8(bStr[i]) - 32);
            } else {
                bUpper[i] = bStr[i];
            }
        }
        return string(bUpper);
    }

    // Helper function to generate date suffix for JSON files
    function getDateSuffix() internal view returns (string memory) {
        return StringHelper.convertTimestampToDateString(block.timestamp, "YYYYMMDD");
    }

    // Helper function to create deployment file path with date suffix
    function getDeploymentFilePath(string memory network, string memory contractType)
        internal
        view
        returns (string memory)
    {
        string memory dateSuffix = getDateSuffix();
        string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", network);
        return string.concat(deploymentsDir, "/", network, "-", contractType, "-", dateSuffix, ".json");
    }
}
