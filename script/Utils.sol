// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../contracts/core/factory/TermMaxFactory.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";
import {ITermMaxFactory} from "../contracts/core/factory/ITermMaxFactory.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../contracts/core/tokens/IGearingToken.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";

library DeployUtils {
    function deployFactory(
        address adminAddr
    ) public returns (TermMaxFactory factory) {
        factory = new TermMaxFactory(adminAddr);
        TermMaxMarket marketImpl = new TermMaxMarket();
        factory.initMarketImplement(address(marketImpl));
    }

    function deployRouter(
        address adminAddr
    ) public returns (TermMaxRouter router) {
        address implementation = address(new TermMaxRouter());
        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, adminAddr);
        address proxy = address(new ERC1967Proxy(implementation, data));
        router = TermMaxRouter(proxy);
        router.togglePause(false);
    }

    function deployMockERC20(
        address adminAddr,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public returns (MockERC20 token) {
        token = new MockERC20(name, symbol, decimals);
    }

    function deployMockPriceFeed(
        address adminAddr,
        int256 price
    ) public returns (MockPriceFeed priceFeed) {
        priceFeed = new MockPriceFeed(adminAddr);
        priceFeed.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: price,
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );
    }

    function deployMarket(
        address adminAddr,
        address factoryAddr,
        address collateralAddr,
        address collateralOracleAddr,
        address underlyingAddr,
        address underlyingOracleAddr,
        bytes32 getKey,
        uint32 liquidationLtv,
        uint32 maxLtv,
        MarketConfig memory marketConfig
    ) public returns (TermMaxMarket market) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: getKey,
                admin: adminAddr,
                collateral: collateralAddr,
                underlying: IERC20Metadata(underlyingAddr),
                underlyingOracle: AggregatorV3Interface(underlyingOracleAddr),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralOracleAddr)
            });
        market = TermMaxMarket(factory.createMarket(params));
    }

    function whitelistMarket(address routerAddr, address marketAddr) public {
        TermMaxRouter router = TermMaxRouter(routerAddr);
        router.setMarketWhitelist(marketAddr, true);
    }
}
