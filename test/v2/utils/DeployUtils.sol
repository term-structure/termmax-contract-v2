// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITermMaxMarket, ITermMaxMarketV2, TermMaxMarketV2} from "contracts/v2/TermMaxMarketV2.sol";
import {ITermMaxOrder, ISwapCallback, TermMaxOrderV2} from "contracts/v2/TermMaxOrderV2.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20} from "contracts/v1/tokens/IMintableERC20.sol";
import {IMintableERC20V2, MintableERC20V2} from "contracts/v2/tokens/MintableERC20V2.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {ITermMaxFactory, TermMaxFactoryV2} from "contracts/v2/factory/TermMaxFactoryV2.sol";
import {TermMaxRouterV2} from "contracts/v2/router/TermMaxRouterV2.sol";
import {IOracleV2, OracleAggregatorV2, AggregatorV3Interface} from "contracts/v2/oracle/OracleAggregatorV2.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {MockOrderV2} from "contracts/v2/test/MockOrderV2.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {OrderManagerV2} from "contracts/v2/vault/OrderManagerV2.sol";
import {TermMaxVaultV2} from "contracts/v2/vault/TermMaxVaultV2.sol";
import {AccessManager} from "contracts/v2/access/AccessManagerV2.sol";
import {
    VaultInitialParams,
    MarketConfig,
    MarketInitialParams,
    LoanConfig,
    OrderConfig,
    CurveCut,
    CurveCuts
} from "contracts/v1/storage/TermMaxStorage.sol";
import {VaultInitialParamsV2} from "contracts/v2/storage/TermMaxStorageV2.sol";
import {TermMaxVaultFactoryV2} from "contracts/v2/factory/TermMaxVaultFactoryV2.sol";
import {MockAave} from "contracts/v2/test/MockAave.sol";
import {MockWhitelistManager, IWhitelistManager} from "contracts/v2/test/MockWhitelistManager.sol";
import {WhitelistManager} from "contracts/v2/access/WhitelistManager.sol";
import {AccessManagerV2} from "contracts/v2/access/AccessManagerV2.sol";
import {
    TermMax4626Factory,
    StableERC4626For4626,
    StableERC4626ForAave,
    VariableERC4626ForAave,
    StableERC4626ForVenus,
    StableERC4626ForCustomize
} from "contracts/v2/factory/TermMax4626Factory.sol";

library DeployUtils {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    struct SwapRange {
        uint256 buyFtMax;
        uint256 buyXtMax;
        uint256 sellFtMax;
        uint256 sellXtMax;
        uint256 buyExactFtMax;
        uint256 buyExactXtMax;
        uint256 sellFtForExactTokenMax;
        uint256 sellXtForExactTokenMax;
    }

    struct Res {
        TermMaxVaultV2 vault;
        AccessManagerV2 accessManager;
        TermMaxVaultFactoryV2 vaultFactory;
        TermMaxFactoryV2 factory;
        TermMax4626Factory poolFactory;
        TermMaxOrderV2 order;
        TermMaxRouterV2 router;
        MarketConfig marketConfig;
        OrderConfig orderConfig;
        TermMaxMarketV2 market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IGearingToken gt;
        MockPriceFeed debtOracle;
        MockPriceFeed collateralOracle;
        OracleAggregatorV2 oracle;
        MockERC20 collateral;
        MockERC20 debt;
        SwapRange swapRange;
        MockAave aave;
        WhitelistManager whitelistManager;
    }

    function grantAllRoles(address to, AccessManagerV2 accessManager) internal {
        accessManager.grantRole(accessManager.MARKET_ROLE(), to);
        accessManager.grantRole(accessManager.ORACLE_ROLE(), to);
        accessManager.grantRole(accessManager.VAULT_ROLE(), to);
        accessManager.grantRole(accessManager.WHITELIST_ROLE(), to);
        accessManager.grantRole(accessManager.UPGRADER_ROLE(), to);
        accessManager.grantRole(accessManager.TERMMAX_MARKET_FACTORY_ROLE(), to);
        accessManager.grantRole(accessManager.TERMMAX_4626_FACTORY_ROLE(), to);
        accessManager.grantRole(accessManager.POOL_DEPLOYER_ROLE(), to);
        accessManager.grantRole(accessManager.VAULT_DEPLOYER_ROLE(), to);
        accessManager.grantRole(accessManager.PAUSER_ROLE(), to);
        accessManager.grantRole(accessManager.CONFIGURATOR_ROLE(), to);
    }

    function deployAccessControl(address admin) internal returns (Res memory res) {
        AccessManagerV2 accessImpl = new AccessManagerV2();
        res.accessManager = AccessManagerV2(
            address(new ERC1967Proxy(address(accessImpl), abi.encodeCall(AccessManager.initialize, admin)))
        );
        res.accessManager.grantRole(res.accessManager.DEFAULT_ADMIN_ROLE(), address(this));
        // grant all roles to the admin
        grantAllRoles(admin, res.accessManager);
        grantAllRoles(address(this), res.accessManager);
        res.whitelistManager = deployWhitelistManager(address(res.accessManager));

        res.oracle = deployOracle(admin, 0);
    }

    function deployMockTokens(Res memory res, address admin) internal returns (Res memory) {
        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.debt = new MockERC20("DAI", "DAI", 8);
        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);

        // set test prices
        res.oracle.submitPendingOracle(
            address(res.debt), IOracleV2.Oracle(res.debtOracle, res.debtOracle, 0, 0, 365 days, 0)
        );
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracleV2.Oracle(res.collateralOracle, res.collateralOracle, 0, 0, 365 days, 0)
        );

        res.oracle.acceptPendingOracle(address(res.debt));
        res.oracle.acceptPendingOracle(address(res.collateral));

        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: int256(1e1 ** res.collateralOracle.decimals()),
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0
        });
        res.collateralOracle.updateRoundData(roundData);
    }

    function deployMarketFactory(address accessManager, address whitelistManager, address orderImplementation)
        internal
        returns (TermMaxFactoryV2 factory)
    {
        address tokenImplementation = address(new MintableERC20V2());
        TermMaxMarketV2 m = new TermMaxMarketV2(tokenImplementation, orderImplementation);
        // use whitelist manager do automatically set whitelist for new market
        factory = new TermMaxFactoryV2(address(accessManager), address(m), whitelistManager);
        // grant MARKET_ROLE to factory so it can set whitelist for new market
        grantWhitelistRoleTo(accessManager, address(factory));
    }

    function deployMarketFactory(address accessManager, address whitelistManager)
        internal
        returns (TermMaxFactoryV2 factory)
    {
        return deployMarketFactory(accessManager, whitelistManager, address(new TermMaxOrderV2()));
    }

    function grantWhitelistRoleTo(address managerAddress, address to) internal {
        AccessManagerV2 manager = AccessManagerV2(managerAddress);
        manager.grantRole(manager.WHITELIST_ROLE(), to);
    }

    function deployVaultFactory(address accessManager, address whitelistManager, address admin)
        internal
        returns (TermMaxVaultFactoryV2 vaultFactory)
    {
        OrderManagerV2 orderManager = new OrderManagerV2();
        TermMaxVaultV2 implementation = new TermMaxVaultV2(address(orderManager), whitelistManager);
        vaultFactory =
            new TermMaxVaultFactoryV2(address(accessManager), address(implementation), address(whitelistManager));
        grantWhitelistRoleTo(accessManager, address(vaultFactory));
    }

    function deployPoolFactory(address accessManager, address whitelistManager, address aave_pool)
        internal
        returns (TermMax4626Factory factory)
    {
        // deploy 4626 factory

        address stableERC4626ForAave;
        address variableERC4626ForAave;
        if (aave_pool != address(0)) {
            stableERC4626ForAave = address(new StableERC4626ForAave(aave_pool, 0));
            variableERC4626ForAave = address(new VariableERC4626ForAave(aave_pool, 0));
        }
        StableERC4626For4626 stableERC4626For4626 = new StableERC4626For4626();
        StableERC4626ForVenus stableERC4626ForVenus = new StableERC4626ForVenus();
        StableERC4626ForCustomize stableERC4626ForCustomize = new StableERC4626ForCustomize();

        factory = new TermMax4626Factory(
            address(accessManager),
            address(stableERC4626For4626),
            stableERC4626ForAave,
            address(stableERC4626ForVenus),
            variableERC4626ForAave,
            address(stableERC4626ForCustomize),
            address(whitelistManager)
        );

        // grant POOL_DEPLOYER_ROLE to factory so it can set whitelist for new pool
        grantWhitelistRoleTo(accessManager, address(factory));
    }

    function deployRes(address admin) internal returns (Res memory res) {
        res = deployAccessControl(admin);
        res.factory = deployMarketFactory(
            address(res.accessManager), address(res.whitelistManager), address(new TermMaxOrderV2())
        );
        res.vaultFactory = deployVaultFactory(address(res.accessManager), address(res.whitelistManager), admin);
        res.poolFactory = deployPoolFactory(address(res.accessManager), address(res.whitelistManager), address(0));
        res.router = deployRouter(admin, address(res.whitelistManager));
    }

    function deployMarket(address admin, MarketConfig memory marketConfig, uint32 maxLtv, uint32 liquidationLtv)
        internal
        returns (Res memory res)
    {
        res = deployAccessControl(admin);
        deployMockTokens(res, admin);
        res.factory = deployMarketFactory(
            address(res.accessManager), address(res.whitelistManager), address(new TermMaxOrderV2())
        );
        res.vaultFactory = deployVaultFactory(address(res.accessManager), address(res.whitelistManager), admin);
        res.poolFactory = deployPoolFactory(address(res.accessManager), address(res.whitelistManager), address(0));

        MarketInitialParams memory initialParams = MarketInitialParams({
            collateral: address(res.collateral),
            debtToken: res.debt,
            admin: admin,
            gtImplementation: address(0),
            marketConfig: marketConfig,
            loanConfig: LoanConfig({
                oracle: IOracle(address(res.oracle)),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true
            }),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });
        res.marketConfig = marketConfig;
        res.market = TermMaxMarketV2(res.factory.createMarket(GT_ERC20, initialParams, 0));

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
    }

    function deployMarket(
        address admin,
        MarketConfig memory marketConfig,
        uint32 maxLtv,
        uint32 liquidationLtv,
        address collateral,
        address debt
    ) internal returns (Res memory res) {
        res = deployAccessControl(admin);
        res.factory = deployMarketFactory(
            address(res.accessManager), address(res.whitelistManager), address(new TermMaxOrderV2())
        );
        res.vaultFactory = deployVaultFactory(address(res.accessManager), address(res.whitelistManager), admin);
        res.poolFactory = deployPoolFactory(address(res.accessManager), address(res.whitelistManager), address(0));

        res.collateral = MockERC20(collateral);
        res.debt = MockERC20(debt);

        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);

        res.oracle.submitPendingOracle(
            address(res.debt), IOracleV2.Oracle(res.debtOracle, res.debtOracle, 0, 0, 365 days, 0)
        );
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracleV2.Oracle(res.collateralOracle, res.collateralOracle, 0, 0, 365 days, 0)
        );
        res.oracle.acceptPendingOracle(address(res.debt));
        res.oracle.acceptPendingOracle(address(res.collateral));

        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: int256(1e1 ** res.collateralOracle.decimals()),
            startedAt: 0,
            updatedAt: 0,
            answeredInRound: 0
        });
        res.collateralOracle.updateRoundData(roundData);

        MarketInitialParams memory initialParams = MarketInitialParams({
            collateral: address(res.collateral),
            debtToken: res.debt,
            admin: admin,
            gtImplementation: address(0),
            marketConfig: marketConfig,
            loanConfig: LoanConfig({
                oracle: IOracle(address(res.oracle)),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true
            }),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });

        res.marketConfig = marketConfig;
        res.market = TermMaxMarketV2(res.factory.createMarket(GT_ERC20, initialParams, 0));

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
    }

    function deployMockMarket(address admin, MarketConfig memory marketConfig, uint32 maxLtv, uint32 liquidationLtv)
        internal
        returns (Res memory res)
    {
        res = deployAccessControl(admin);
        deployMockTokens(res, admin);
        res.factory =
            deployMarketFactory(address(res.accessManager), address(res.whitelistManager), address(new MockOrderV2()));
        res.vaultFactory = deployVaultFactory(address(res.accessManager), address(res.whitelistManager), admin);
        res.poolFactory = deployPoolFactory(address(res.accessManager), address(res.whitelistManager), address(0));

        MarketInitialParams memory initialParams = MarketInitialParams({
            collateral: address(res.collateral),
            debtToken: res.debt,
            admin: admin,
            gtImplementation: address(0),
            marketConfig: marketConfig,
            loanConfig: LoanConfig({
                oracle: IOracle(address(res.oracle)),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true
            }),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });
        res.marketConfig = marketConfig;
        res.market = TermMaxMarketV2(res.factory.createMarket(GT_ERC20, initialParams, 0));

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
    }

    function deployOrder(
        ITermMaxMarket market,
        address maker,
        uint256 maxXtReserve,
        ISwapCallback swapTrigger,
        CurveCuts memory curveCuts
    ) public returns (ITermMaxOrder order) {
        order = market.createOrder(maker, maxXtReserve, swapTrigger, curveCuts);
    }

    function deployRouter(address admin, address whitelistManager) public returns (TermMaxRouterV2 router) {
        TermMaxRouterV2 implementation = new TermMaxRouterV2(whitelistManager);
        bytes memory data = abi.encodeCall(TermMaxRouterV2.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouterV2(address(proxy));
    }

    function deployVault(TermMaxVaultFactoryV2 vaultFactory, VaultInitialParamsV2 memory initialParams)
        public
        returns (TermMaxVaultV2 vault)
    {
        vault = TermMaxVaultV2(vaultFactory.createVault(initialParams, 0));
    }

    function deployVault(TermMaxVaultFactoryV2 vaultFactory, VaultInitialParamsV2 memory initialParams, uint256 salt)
        public
        returns (TermMaxVaultV2 vault)
    {
        vault = TermMaxVaultV2(vaultFactory.createVault(initialParams, salt));
    }

    function deployOracle(address admin, uint256 timeLock) public returns (OracleAggregatorV2 oracle) {
        oracle = new OracleAggregatorV2(admin, timeLock);
    }

    function deployAccessManager(address admin) internal returns (AccessManager accessManager) {
        AccessManager implementation = new AccessManager();
        bytes memory data = abi.encodeCall(AccessManager.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        accessManager = AccessManager(address(proxy));
    }

    function deployWhitelistManager(address accessManagerAddress)
        internal
        returns (WhitelistManager whitelistManager)
    {
        WhitelistManager whitelistManagerImpl = new WhitelistManager(accessManagerAddress);
        whitelistManager = WhitelistManager(
            address(
                new ERC1967Proxy(
                    address(whitelistManagerImpl), abi.encodeCall(WhitelistManager.initialize, (accessManagerAddress))
                )
            )
        );
    }
}
