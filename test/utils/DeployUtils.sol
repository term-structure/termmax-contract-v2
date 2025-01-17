// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ITermMaxMarket, TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {ITermMaxOrder, ISwapCallback, TermMaxOrder} from "contracts/TermMaxOrder.sol";
import {MockERC20, ERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {IMintableERC20, MintableERC20} from "contracts/tokens/MintableERC20.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {ITermMaxFactory, TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";
import "contracts/storage/TermMaxStorage.sol";

library DeployUtils {
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");
    struct Res {
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
    }

    function deployMarket(
        address admin,
        MarketConfig memory marketConfig,
        uint32 maxLtv,
        uint32 liquidationLtv
    ) internal returns (Res memory res) {
        res.factory = deployFactory(admin);

        res.collateral = new MockERC20("ETH", "ETH", 18);
        res.debt = new MockERC20("DAI", "DAI", 8);

        res.debtOracle = new MockPriceFeed(admin);
        res.collateralOracle = new MockPriceFeed(admin);
        res.oracle = deployOracle(admin);

        res.oracle.setOracle(address(res.debt), IOracle.Oracle(res.debtOracle, res.debtOracle, 365 days));
        res.oracle.setOracle(
            address(res.collateral),
            IOracle.Oracle(res.collateralOracle, res.collateralOracle, 365 days)
        );

        MockPriceFeed.RoundData memory roundData = MockPriceFeed.RoundData({
            roundId: 1,
            answer: int(1e1 ** res.collateralOracle.decimals()),
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
                oracle: res.oracle,
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true
            }),
            gtInitalParams: abi.encode(type(uint256).max),
            tokenName: "DAI-ETH",
            tokenSymbol: "DAI-ETH"
        });

        res.marketConfig = marketConfig;
        res.market = ITermMaxMarket(res.factory.createMarket(GT_ERC20, initialParams, 0));

        (res.ft, res.xt, res.gt, , ) = res.market.tokens();
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

    function deployOracle(address admin) public returns (OracleAggregator oracle) {
        OracleAggregator implementation = new OracleAggregator();
        bytes memory data = abi.encodeCall(OracleAggregator.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        oracle = OracleAggregator(address(proxy));
    }

    function deployRouter(address admin) public returns (TermMaxRouter router) {
        TermMaxRouter implementation = new TermMaxRouter();
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        router = TermMaxRouter(address(proxy));
    }

    // function deployAccessManager(address admin) internal returns (AccessManager accessManager) {
    //     AccessManager implementation = new AccessManager();
    //     bytes memory data = abi.encodeCall(AccessManager.initialize, admin);
    //     ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
    //     accessManager = AccessManager(address(proxy));
    // }
}
