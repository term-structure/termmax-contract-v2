// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITermMaxMarket, TermMaxMarket} from "contracts/v1/TermMaxMarket.sol";
import {ITermMaxOrder, ISwapCallback, TermMaxOrder} from "contracts/v1/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/v1/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/v1/test/MockPriceFeed.sol";
import {IMintableERC20, MintableERC20} from "contracts/v1/tokens/MintableERC20.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";
import {ITermMaxFactory, TermMaxFactory} from "contracts/v1/factory/TermMaxFactory.sol";
import {TermMaxRouter} from "contracts/v1/router/TermMaxRouter.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/v1/oracle/OracleAggregator.sol";
import {MockOrder} from "contracts/v1/test/MockOrder.sol";
import {VaultFactory, IVaultFactory} from "contracts/v1/factory/VaultFactory.sol";
import {OrderManager} from "contracts/v1/vault/OrderManager.sol";
import {TermMaxVault, ITermMaxVault} from "contracts/v1/vault/TermMaxVault.sol";
import {AccessManager} from "contracts/v1/access/AccessManager.sol";
import "contracts/v1/storage/TermMaxStorage.sol";

library DeployUtils {
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
        ITermMaxVault vault;
        IVaultFactory vaultFactory;
        TermMaxFactory factory;
        ITermMaxOrder order;
        TermMaxRouter router;
        MarketConfig marketConfig;
        OrderConfig orderConfig;
        ITermMaxMarket market;
        IMintableERC20 ft;
        IMintableERC20 xt;
        IGearingToken gt;
        MockPriceFeed debtOracle;
        MockPriceFeed collateralOracle;
        OracleAggregator oracle;
        MockERC20 collateral;
        MockERC20 debt;
        SwapRange swapRange;
    }

    function deployMarket(address admin, MarketConfig memory marketConfig, uint32 maxLtv, uint32 liquidationLtv)
        internal
        returns (Res memory res)
    {
        res.factory = deployFactory(admin);

        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.debt = new MockERC20("DAI", "DAI", 8);

        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);
        res.oracle = deployOracle(admin, 0);

        res.oracle.submitPendingOracle(address(res.debt), IOracle.Oracle(res.debtOracle, res.debtOracle, 365 days));
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
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
            loanConfig: LoanConfig({oracle: res.oracle, liquidationLtv: liquidationLtv, maxLtv: maxLtv, liquidatable: true}),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });

        res.marketConfig = marketConfig;
        res.market = ITermMaxMarket(res.factory.createMarket(GT_ERC20, initialParams, 0));

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
        res.factory = deployFactory(admin);

        res.collateral = MockERC20(collateral);
        res.debt = MockERC20(debt);

        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);
        res.oracle = deployOracle(admin, 0);

        res.oracle.submitPendingOracle(address(res.debt), IOracle.Oracle(res.debtOracle, res.debtOracle, 365 days));
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
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
            loanConfig: LoanConfig({oracle: res.oracle, liquidationLtv: liquidationLtv, maxLtv: maxLtv, liquidatable: true}),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });

        res.marketConfig = marketConfig;
        res.market = ITermMaxMarket(res.factory.createMarket(GT_ERC20, initialParams, 0));

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
    }

    function deployMockMarket2(
        address admin,
        IERC20 debt,
        uint256 duration,
        MarketConfig memory mc,
        uint32 maxLtv,
        uint32 liquidationLtv
    ) internal returns (Res memory res) {
        res.factory = deployFactoryWithMockOrder(admin);
        res.debt = MockERC20(address(debt));
        MarketConfig memory marketConfig = mc;
        marketConfig.maturity += uint64(duration * 1 days);

        res.collateral = new MockERC20("ETH", "ETH", 18);

        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);
        res.oracle = deployOracle(admin, 0);

        res.oracle.submitPendingOracle(address(res.debt), IOracle.Oracle(res.debtOracle, res.debtOracle, 365 days));
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
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
            loanConfig: LoanConfig({oracle: res.oracle, liquidationLtv: liquidationLtv, maxLtv: maxLtv, liquidatable: true}),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });

        res.marketConfig = marketConfig;
        res.market = ITermMaxMarket(res.factory.createMarket(GT_ERC20, initialParams, 0));

        (res.ft, res.xt, res.gt,,) = res.market.tokens();
    }

    function deployMockMarket(address admin, MarketConfig memory marketConfig, uint32 maxLtv, uint32 liquidationLtv)
        internal
        returns (Res memory res)
    {
        res.factory = deployFactoryWithMockOrder(admin);

        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.debt = new MockERC20("DAI", "DAI", 8);

        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);
        res.oracle = deployOracle(admin, 0);

        res.oracle.submitPendingOracle(address(res.debt), IOracle.Oracle(res.debtOracle, res.debtOracle, 365 days));
        res.oracle.submitPendingOracle(
            address(res.collateral), IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
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
            loanConfig: LoanConfig({oracle: res.oracle, liquidationLtv: liquidationLtv, maxLtv: maxLtv, liquidatable: true}),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });

        res.marketConfig = marketConfig;
        res.market = ITermMaxMarket(res.factory.createMarket(GT_ERC20, initialParams, 0));

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

    function deployOracle(address admin, uint256 timeLock) public returns (OracleAggregator oracle) {
        oracle = new OracleAggregator(admin, timeLock);
    }

    function deployRouter(address admin) public returns (TermMaxRouter router) {
        TermMaxRouter implementation = new TermMaxRouter();
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouter(address(proxy));
    }

    function deployVault(VaultInitialParams memory initialParams) public returns (ITermMaxVault vault) {
        OrderManager orderManager = new OrderManager();
        TermMaxVault implementation = new TermMaxVault(address(orderManager));
        VaultFactory vaultFactory = new VaultFactory(address(implementation));

        vault = ITermMaxVault(vaultFactory.createVault(initialParams, 0));
    }

    function deployAccessManager(address admin) internal returns (AccessManager accessManager) {
        AccessManager implementation = new AccessManager();
        bytes memory data = abi.encodeCall(AccessManager.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        accessManager = AccessManager(address(proxy));
    }
}
