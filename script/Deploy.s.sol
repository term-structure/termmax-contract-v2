// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken, AggregatorV3Interface} from "../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeployMainnetFork is Script {
    // deployer config
    uint256 deployerPrivateKey = vm.envUint("FORK_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);

    // market config
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");
    MarketConfig marketConfig =
        MarketConfig({
            treasurer: 0x944a0Af591E2C23a2E81fe4c10Bd9c47Cf866F4b,
            maturity: 1735575942, // current 1726732382
            openTime: uint64(vm.getBlockTimestamp() + 200),
            apr: 12000000,
            lsf: 80000000,
            lendFeeRatio: 3000000,
            minNLendFeeR: 3000000,
            borrowFeeRatio: 3000000,
            minNBorrowFeeR: 3000000,
            redeemFeeRatio: 50000000,
            issueFtFeeRatio: 10000000,
            lockingPercentage: 50000000,
            initialLtv: 88000000,
            protocolFeeRatio: 50000000,
            rewardIsDistributed: true
        });
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    // oracle config
    address underlyingAddr =
        address(0x103bE36C56F72a05e19CE8f9e70a70d33cCe0421); // USDC
    address underlyingOracleAddr =
        address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    address collateralAddr =
        address(0xE73362b23CafAc6559aA3101d2f80fed474b09bF); // PT-sUSDe-24OCT2024
    address collateralOracleAddr =
        address(0xD752C02f557580cEC3a50a2deBF3A4C48657EeDe);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TermMaxFactory factory = deployFactory(deployerAddr);
        TermMaxRouter router = deployRouter(deployerAddr);
        (
            MockERC20 usdc,
            MockERC20 pt,
            MockPriceFeed usdcOracle,
            MockPriceFeed ptOracle
        ) = deployMockERC20();
        TermMaxMarket market = deployMarket(
            deployerAddr,
            address(factory),
            address(pt),
            address(usdc),
            address(ptOracle),
            address(usdcOracle)
        );
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingToken gt,
            address collateral,
            IERC20 underlying
        ) = market.tokens();
        whitelistMarket(address(router), address(market), address(collateral));
        vm.stopBroadcast();
        // provdieLiquidity(router, market);
        MarketConfig memory config = market.config();
        console.log("Deploying TermMax Factory with deplyer:", deployerAddr);
        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));
        console.log("Market deployed at:", address(market));
        console.log(
            "Collateral (%s) deployed at: %s",
            IERC20Metadata(collateral).symbol(),
            address(collateral)
        );
        console.log("Collateral Oracle deployed at:", address(ptOracle));
        console.log(
            "Underlying (%s) deployed at: %s",
            IERC20Metadata(address(underlying)).symbol(),
            address(underlying)
        );
        console.log("Underlying Oracle deployed at:", address(usdcOracle));
        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("LPFT deployed at:", address(lpFt));
        console.log("LPXT deployed at:", address(lpXt));
        console.log("GT deployed at:", address(gt));
        console.log("Market open time:", config.openTime);
    }

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
    }

    function deployMockERC20()
        public
        returns (
            MockERC20 USDC,
            MockERC20 PT,
            MockPriceFeed usdcOracle,
            MockPriceFeed ptOracle
        )
    {
        USDC = new MockERC20("Mock USDC", "USDC", 6);
        PT = new MockERC20("Mock PT-sUSDe", "PT-sUSDe", 18);
        usdcOracle = new MockPriceFeed(deployerAddr);
        usdcOracle.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: 1e8,
                startedAt: vm.getBlockTimestamp(),
                updatedAt: vm.getBlockTimestamp(),
                answeredInRound: 1
            })
        );
        ptOracle = new MockPriceFeed(deployerAddr);
        ptOracle.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: 95e6,
                startedAt: vm.getBlockTimestamp(),
                updatedAt: vm.getBlockTimestamp(),
                answeredInRound: 1
            })
        );
    }

    function deployMarket(
        address adminAddr,
        address factoryAddr,
        address collateralAddr,
        address underlyingAddr,
        address collateralOracleAddr,
        address underlyingOracleAddr
    ) public returns (TermMaxMarket market) {
        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: GT_ERC20,
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

    function whitelistMarket(
        address routerAddr,
        address marketAddr,
        address collateralAddr
    ) public {
        TermMaxRouter router = TermMaxRouter(routerAddr);
        router.setMarketWhitelist(marketAddr, true);
        router.togglePause(false);
    }

    function provdieLiquidity(
        TermMaxRouter router,
        TermMaxMarket market
    ) public {
        (, , , , , , IERC20 underlying) = market.tokens();
        uint256 amount = 1000e6;
        MockERC20(address(underlying)).mint(address(this), amount);
        underlying.approve(address(router), amount);
        router.provideLiquidity(address(this), market, amount);
    }
}
