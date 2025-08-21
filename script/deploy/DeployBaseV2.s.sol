// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {TermMaxFactoryV2, ITermMaxFactory} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {MakerHelper} from "contracts/v2/router/MakerHelper.sol";
import {MarketViewer} from "contracts/v1/router/MarketViewer.sol";
import {ITermMaxRouter} from "contracts/v1/router/ITermMaxRouter.sol";
import {TermMaxMarketV2} from "contracts/v2/TermMaxMarketV2.sol";
import {TermMaxOrderV2} from "contracts/v2/TermMaxOrderV2.sol";
import {MockERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20V2, MintableERC20V2} from "contracts/v2/tokens/MintableERC20V2.sol";
import {SwapAdapterV2} from "contracts/v2/test/testnet/SwapAdapterV2.sol";
import {Faucet} from "contracts/v1/test/testnet/Faucet.sol";
import {JsonLoader} from "../utils/JsonLoader.sol";
import {FaucetERC20} from "contracts/v1/test/testnet/FaucetERC20.sol";
import {IOracleV2, OracleAggregatorV2} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {IOrderManagerV2, OrderManagerV2} from "contracts/v2/vault/OrderManagerV2.sol";
import {ITermMaxVaultV2, TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {TermMaxVaultFactoryV2, ITermMaxVaultFactoryV2} from "contracts/v2/factory/TermMaxVaultFactoryV2.sol";
import {
    MarketConfig,
    FeeConfig,
    MarketInitialParams,
    LoanConfig,
    VaultInitialParams
} from "contracts/v1/storage/TermMaxStorage.sol";
import {VaultInitialParamsV2, OrderInitialParams} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {ERC4626VaultAdapterV2} from "contracts/v2/router/swapAdapters/ERC4626VaultAdapterV2.sol";
import {OdosV2AdapterV2} from "contracts/v2/router/swapAdapters/OdosV2AdapterV2.sol";
import {PendleSwapV3AdapterV2} from "contracts/v2/router/swapAdapters/PendleSwapV3AdapterV2.sol";
import {UniswapV3AdapterV2} from "contracts/v2/router/swapAdapters/UniswapV3AdapterV2.sol";
import {TermMaxSwapAdapter} from "contracts/v2/router/swapAdapters/TermMaxSwapAdapter.sol";
import {AccessManagerV2, AccessManager} from "contracts/v2/access/AccessManagerV2.sol";
import {StringHelper} from "../utils/StringHelper.sol";

contract DeployBaseV2 is Script {
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    function deployFactory(address admin) public returns (TermMaxFactoryV2 factory) {
        address tokenImplementation = address(new MintableERC20V2());
        address orderImplementation = address(new TermMaxOrderV2());
        TermMaxMarketV2 m = new TermMaxMarketV2(tokenImplementation, orderImplementation);
        factory = new TermMaxFactoryV2(admin, address(m));
    }

    function deployVaultFactory() public returns (TermMaxVaultFactoryV2 vaultFactory) {
        OrderManagerV2 orderManager = new OrderManagerV2();
        TermMaxVaultV2 implementation = new TermMaxVaultV2(address(orderManager));
        vaultFactory = new TermMaxVaultFactoryV2(address(implementation));
    }

    function deployOracleAggregator(address admin, uint256 timelock) public returns (OracleAggregatorV2 oracle) {
        oracle = new OracleAggregatorV2(admin, timelock);
    }

    function deployRouter(address admin) public returns (TermMaxRouterV2 router) {
        TermMaxRouterV2 implementation = new TermMaxRouterV2();

        bytes memory data = abi.encodeCall(TermMaxRouterV2.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouterV2(address(proxy));
    }

    function upgradeRouter(AccessManagerV2 manager, address routerProxy) public returns (TermMaxRouterV2 router) {
        TermMaxRouterV2 implementation = new TermMaxRouterV2();
        manager.upgradeSubContract(UUPSUpgradeable(routerProxy), address(implementation), bytes(""));
        router = TermMaxRouterV2(routerProxy);
    }

    function deployMakerHelper(address admin) public returns (MakerHelper makerHelper) {
        address implementation = address(new MakerHelper());
        bytes memory data = abi.encodeCall(MakerHelper.initialize, admin);
        address proxy = address(new ERC1967Proxy(address(implementation), data));
        makerHelper = MakerHelper(proxy);
    }

    function deployAccessManager(address admin) public returns (AccessManagerV2 accessManager) {
        AccessManagerV2 implementation = new AccessManagerV2();

        bytes memory data = abi.encodeCall(AccessManager.initialize, admin);
        address proxy = address(new ERC1967Proxy(address(implementation), data));
        accessManager = AccessManagerV2(proxy);
    }

    function upgradeAccessManager(address accessmanagerProxy) public returns (AccessManagerV2 accessManager) {
        AccessManagerV2 implementation = new AccessManagerV2();
        AccessManagerV2 existingAccessManager = AccessManagerV2(accessmanagerProxy);
        existingAccessManager.upgradeToAndCall(address(implementation), "");
        return existingAccessManager;
    }

    function deployCore(address deployerAddr, address accessManagerAddr, uint256 oracleTimelock)
        public
        returns (
            TermMaxFactoryV2 factory,
            TermMaxVaultFactoryV2 vaultFactory,
            OracleAggregatorV2 oracleAggregator,
            TermMaxRouterV2 router,
            MakerHelper makerHelper,
            SwapAdapterV2 swapAdapter,
            Faucet faucet,
            MarketViewer marketViewer
        )
    {
        // deploy access manager
        AccessManagerV2 accessManager = AccessManagerV2(accessManagerAddr);

        // deploy factory
        factory = deployFactory(address(accessManager));

        // deploy vault factory
        vaultFactory = deployVaultFactory();

        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(address(accessManager), oracleTimelock);

        // deploy router
        router = deployRouter(address(accessManager));

        // deploy swap adapter
        swapAdapter = new SwapAdapterV2(deployerAddr);
        accessManager.setAdapterWhitelist(ITermMaxRouter(address(router)), address(swapAdapter), true);

        faucet = new Faucet(deployerAddr);

        // deploy market viewer
        marketViewer = deployMarketViewer();

        // deploy maker helper
        makerHelper = deployMakerHelper(address(accessManager));
    }

    function deployAndUpgradeCore(
        address deployerAddr,
        address accessManagerAddr,
        address routerAddr,
        uint256 oracleTimelock
    )
        public
        returns (
            TermMaxFactoryV2 factory,
            TermMaxVaultFactoryV2 vaultFactory,
            OracleAggregatorV2 oracleAggregator,
            TermMaxRouterV2 router,
            MakerHelper makerHelper,
            SwapAdapterV2 swapAdapter
        )
    {
        // deploy access manager
        AccessManagerV2 accessManager = AccessManagerV2(accessManagerAddr);

        // deploy factory
        factory = deployFactory(address(accessManager));

        // deploy vault factory
        vaultFactory = deployVaultFactory();

        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(address(accessManager), oracleTimelock);

        // deploy and upgrade router
        router = upgradeRouter(accessManager, routerAddr);

        // deploy swap adapter
        swapAdapter = new SwapAdapterV2(deployerAddr);
        accessManager.setAdapterWhitelist(ITermMaxRouter(address(router)), address(swapAdapter), true);

        // deploy maker helper
        makerHelper = deployMakerHelper(address(accessManager));
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
            TermMaxFactoryV2 factory,
            TermMaxVaultFactoryV2 vaultFactory,
            OracleAggregatorV2 oracleAggregator,
            TermMaxRouterV2 router,
            MakerHelper makerHelper,
            MarketViewer marketViewer,
            UniswapV3AdapterV2 uniswapV3Adapter,
            OdosV2AdapterV2 odosV2Adapter,
            PendleSwapV3AdapterV2 pendleSwapV3Adapter,
            ERC4626VaultAdapterV2 vaultAdapter,
            TermMaxSwapAdapter termMaxSwapAdapterV2
        )
    {
        // deploy access manager
        AccessManagerV2 accessManager = AccessManagerV2(accessManagerAddr);

        // deploy factory
        factory = deployFactory(address(accessManager));

        // deploy vault factory
        vaultFactory = deployVaultFactory();

        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(address(accessManager), oracleTimelock);

        // deploy router
        router = deployRouter(address(accessManager));

        // deploy maker helper
        makerHelper = deployMakerHelper(address(accessManager));

        // deploy market viewer
        marketViewer = deployMarketViewer();

        // deploy and whitelist swap adapter
        uniswapV3Adapter = new UniswapV3AdapterV2(address(uniswapV3Router));
        odosV2Adapter = new OdosV2AdapterV2(odosV2Router);
        pendleSwapV3Adapter = new PendleSwapV3AdapterV2(address(pendleSwapV3Router));
        vaultAdapter = new ERC4626VaultAdapterV2();
        termMaxSwapAdapterV2 = new TermMaxSwapAdapter();

        ITermMaxRouter irouter = ITermMaxRouter(address(router));

        accessManager.setAdapterWhitelist(irouter, address(uniswapV3Adapter), true);
        accessManager.setAdapterWhitelist(irouter, address(odosV2Adapter), true);
        accessManager.setAdapterWhitelist(irouter, address(pendleSwapV3Adapter), true);
        accessManager.setAdapterWhitelist(irouter, address(vaultAdapter), true);
        accessManager.setAdapterWhitelist(irouter, address(termMaxSwapAdapterV2), true);
    }

    function deployAndUpgradeCoreMainnet(
        address accessManagerAddr,
        address routerAddr,
        address uniswapV3Router,
        address odosV2Router,
        address pendleSwapV3Router,
        uint256 oracleTimelock
    )
        public
        returns (
            TermMaxFactoryV2 factory,
            TermMaxVaultFactoryV2 vaultFactory,
            OracleAggregatorV2 oracleAggregator,
            TermMaxRouterV2 router,
            MakerHelper makerHelper,
            UniswapV3AdapterV2 uniswapV3Adapter,
            OdosV2AdapterV2 odosV2Adapter,
            PendleSwapV3AdapterV2 pendleSwapV3Adapter,
            ERC4626VaultAdapterV2 vaultAdapter,
            TermMaxSwapAdapter termMaxSwapAdapterV2
        )
    {
        (uniswapV3Adapter, odosV2Adapter, pendleSwapV3Adapter, vaultAdapter, termMaxSwapAdapterV2) =
            deployAdapters(accessManagerAddr, routerAddr, uniswapV3Router, odosV2Router, pendleSwapV3Router);
        // upgrade router
        router = upgradeRouter(AccessManagerV2(accessManagerAddr), routerAddr);
        // deploy factory
        factory = deployFactory(address(AccessManagerV2(accessManagerAddr)));
        // deploy vault factory
        vaultFactory = deployVaultFactory();
        // deploy oracle aggregator
        oracleAggregator = deployOracleAggregator(address(AccessManagerV2(accessManagerAddr)), oracleTimelock);
        // deploy maker helper
        makerHelper = deployMakerHelper(address(AccessManagerV2(accessManagerAddr)));
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
            ERC4626VaultAdapterV2 vaultAdapter,
            TermMaxSwapAdapter termMaxSwapAdapterV2
        )
    {
        // deploy access manager
        AccessManagerV2 accessManager = AccessManagerV2(accessManagerAddr);

        // deploy router
        TermMaxRouterV2 router = TermMaxRouterV2(routerAddr);

        // deploy and whitelist swap adapter
        uniswapV3Adapter = new UniswapV3AdapterV2(address(uniswapV3Router));
        odosV2Adapter = new OdosV2AdapterV2(odosV2Router);
        pendleSwapV3Adapter = new PendleSwapV3AdapterV2(address(pendleSwapV3Router));
        vaultAdapter = new ERC4626VaultAdapterV2();
        termMaxSwapAdapterV2 = new TermMaxSwapAdapter();

        ITermMaxRouter irouter = ITermMaxRouter(address(router));

        accessManager.setAdapterWhitelist(irouter, address(uniswapV3Adapter), true);
        accessManager.setAdapterWhitelist(irouter, address(odosV2Adapter), true);
        accessManager.setAdapterWhitelist(irouter, address(pendleSwapV3Adapter), true);
        accessManager.setAdapterWhitelist(irouter, address(vaultAdapter), true);
        accessManager.setAdapterWhitelist(irouter, address(termMaxSwapAdapterV2), true);
    }

    function deployMarkets(
        address accessManagerAddr,
        address factoryAddr,
        address oracleAddr,
        address faucetAddr,
        string memory deployDataPath,
        address treasurerAddr,
        address priceFeedOperatorAddr
    ) public returns (TermMaxMarketV2[] memory markets, JsonLoader.Config[] memory configs) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        AccessManagerV2 accessManager = AccessManagerV2(accessManagerAddr);
        IOracleV2 oracle = IOracleV2(oracleAddr);
        Faucet faucet = Faucet(faucetAddr);

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        markets = new TermMaxMarketV2[](configs.length);

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
                    oracle, address(collateral), IOracleV2.Oracle(collateralPriceFeed, collateralPriceFeed, 0, 0, 0, 0)
                );
                accessManager.acceptPendingOracle(IOracle(address(oracle)), address(collateral));
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
                    oracle, address(underlying), IOracleV2.Oracle(underlyingPriceFeed, underlyingPriceFeed, 0, 0, 0, 0)
                );
                accessManager.acceptPendingOracle(IOracle(address(oracle)), address(underlying));
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
                    oracle: IOracle(address(oracle)),
                    liquidationLtv: config.loanConfig.liquidationLtv,
                    maxLtv: config.loanConfig.maxLtv,
                    liquidatable: config.loanConfig.liquidatable
                }),
                gtInitalParams: abi.encode(type(uint256).max),
                tokenName: config.marketName,
                tokenSymbol: config.marketSymbol
            });

            TermMaxMarketV2 market =
                TermMaxMarketV2(accessManager.createMarket(factory, GT_ERC20, initialParams, config.salt));
            markets[i] = market;
        }
    }

    function deployMarketsMainnet(
        address accessManagerAddr,
        address factoryAddr,
        address oracleAddr,
        string memory deployDataPath,
        address treasurerAddr
    ) public returns (TermMaxMarketV2[] memory markets, JsonLoader.Config[] memory configs) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        OracleAggregatorV2 oracle = OracleAggregatorV2(oracleAddr);

        string memory deployData = vm.readFile(deployDataPath);

        configs = JsonLoader.getConfigsFromJson(deployData);

        markets = new TermMaxMarketV2[](configs.length);

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
                    oracle: IOracle(address(oracle)),
                    liquidationLtv: config.loanConfig.liquidationLtv,
                    maxLtv: config.loanConfig.maxLtv,
                    liquidatable: config.loanConfig.liquidatable
                }),
                gtInitalParams: abi.encode(config.collateralCapForGt),
                tokenName: config.marketName,
                tokenSymbol: config.marketSymbol
            });
            AccessManagerV2 accessManager = AccessManagerV2(accessManagerAddr);
            TermMaxMarketV2 market =
                TermMaxMarketV2(accessManager.createMarket(factory, GT_ERC20, initialParams, config.salt));
            markets[i] = market;
        }
    }

    function deployVault(address factoryAddr, VaultInitialParamsV2 memory initialParams)
        public
        returns (TermMaxVaultV2 vault)
    {
        TermMaxVaultFactoryV2 vaultFactory = TermMaxVaultFactoryV2(factoryAddr);
        // VaultInitialParamsV2 memory initialParams = VaultInitialParamsV2({
        //     admin: accessManagerAddr,
        //     curator: curator,
        //     guardian: guardian,
        //     timelock: timelock,
        //     asset: IERC20(assetAddr),
        //     pool: IERC4626(address(0)), // No pool for now, can be set later
        //     maxCapacity: maxCapacity,
        //     name: name,
        //     symbol: symbol,
        //     performanceFeeRate: performanceFeeRate,
        //     minApy: minApy
        // });
        vault = TermMaxVaultV2(vaultFactory.createVault(initialParams, 0));
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
