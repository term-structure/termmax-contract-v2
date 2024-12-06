// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ITermMaxFactory, TermMaxFactory} from "../contracts/core/factory/TermMaxFactory.sol";
import {TermMaxRouter} from "../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket, ITermMaxMarket} from "../contracts/core/TermMaxMarket.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken} from "../contracts/core/tokens/IGearingToken.sol";
import {IOracle, OracleAggregator, AggregatorV3Interface} from "contracts/core/oracle/OracleAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UniswapV3Adapter, ERC20SwapAdapter} from "contracts/router/swapAdapters/UniswapV3Adapter.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";

bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

contract FactoryScript is Script {
    // put your config here
    address admin;

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;
        console.log("Deploy TermMax factory with deployer", deployer);
        console.log("--------------------------------------------------");
        TermMaxFactory factory = new TermMaxFactory(deployer);
        console.log("TermMax factory deloy at", address(factory));
        TermMaxMarket m = new TermMaxMarket();
        console.log("TermMax market implementation deloy at", address(m));
        console.log(
            "GearingTokenWithERC20 implementation deloy at",
            factory.gtImplements(GT_ERC20)
        );
        console.log(
            "MintableERC20 implementation deloy at",
            factory.tokenImplement()
        );
        factory.initMarketImplement(address(m));
        factory.transferOwnership(admin);
        vm.stopBroadcast();
    }
}

contract OracleScript is Script {
    // put your config here
    address admin; 

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;
        console.log("Deploy OracleAggregator with deployer", deployer);
        console.log("--------------------------------------------------");
        OracleAggregator implementation = new OracleAggregator();
        bytes memory data = abi.encodeCall(OracleAggregator.initialize, deployer);
        ERC1967Proxy oracle = new ERC1967Proxy(
            address(implementation),
            data
        );
        console.log("OracleAggregator deloy at", address(oracle));

        OracleAggregator(address(oracle)).transferOwnership(admin);
        vm.stopBroadcast();
    }
}

contract MarketScript is Script {
    // put your market config here
    address admin;
    address treasurer;
    address factoryAddr;

    address collateralAddr;
    address underlyingAddr;
    address oracleAggregator;

    uint64 maturity;
    uint64 openTime;
    // The decimals of the following parameters is 8
    uint32 liquidationLtv;
    uint32 maxLtv;
    int64 apr;
    uint32 lsf;
    uint32 lendFeeRatio;
    uint32 minNLendFeeR;
    uint32 borrowFeeRatio;
    uint32 minNBorrowFeeR;
    uint32 redeemFeeRatio;
    uint32 issueFtFeeRatio;
    uint32 lockingPercentage;
    uint32 initialLtv;
    uint32 protocolFeeRatio;
    uint256 collateralCapacity;

    function run() public {
        vm.startBroadcast();

        ITermMaxFactory factory = ITermMaxFactory(factoryAddr);
        address deployer = msg.sender;
        console.log("Deploy TermMax market with deployer", deployer);
        console.log("--------------------------------------------------");
        MarketConfig memory marketConfig = MarketConfig({
            treasurer: treasurer,
            maturity: maturity,
            openTime: openTime,
            apr: apr,
            lsf: lsf,
            lendFeeRatio: lendFeeRatio,
            minNLendFeeR: minNLendFeeR,
            borrowFeeRatio: borrowFeeRatio,
            minNBorrowFeeR: minNBorrowFeeR,
            redeemFeeRatio: redeemFeeRatio,
            issueFtFeeRatio: issueFtFeeRatio,
            lockingPercentage: lockingPercentage,
            initialLtv: initialLtv,
            protocolFeeRatio: protocolFeeRatio,
            rewardIsDistributed: false
        });
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: GT_ERC20,
                admin: admin,
                collateral: collateralAddr,
                underlying: IERC20Metadata(underlyingAddr),
                oracle: IOracle(oracleAggregator),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(collateralCapacity)
            });
        ITermMaxMarket market = ITermMaxMarket(factory.createMarket(params));
        console.log("TermMax market deloy at", address(market));
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingToken gt,
            ,

        ) = market.tokens();
        console.log("TermMax FT token deloy at", address(ft));
        console.log("TermMax XT token deloy at", address(xt));
        console.log("TermMax LpFt token deloy at", address(lpFt));
        console.log("TermMax LpXt token deloy at", address(lpXt));
        console.log("TermMax GT token deloy at", address(gt));
        vm.stopBroadcast();
    }
}

contract RouterScript is Script {
    // put your config here
    address admin;
    address uniswapV3Router;
    address pendleSwapV3Router;

    function run() public {
        vm.startBroadcast();
        address deployer = msg.sender;
        console.log("Deploy TermMax router with deployer", deployer);
        console.log("--------------------------------------------------");

        TermMaxRouter routerImplemention = new TermMaxRouter();
        console.log(
            "TermMax router implementation deloy at",
            address(routerImplemention)
        );

        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, deployer);
        ERC1967Proxy routerProxy = new ERC1967Proxy(
            address(routerImplemention),
            data
        );

        console.log("TermMax router proxy deloy at", address(routerProxy));

        TermMaxRouter router = TermMaxRouter(address(routerProxy));

        UniswapV3Adapter uniswapAdapter = new UniswapV3Adapter(uniswapV3Router);
        console.log("UniswapV3Adapter deloy at", address(uniswapAdapter));
        PendleSwapV3Adapter pendleAdapter = new PendleSwapV3Adapter(
            pendleSwapV3Router
        );
        console.log("PendleSwapV3Adapter deloy at", address(pendleAdapter));

        router.setAdapterWhitelist(address(uniswapAdapter), true);
        router.setAdapterWhitelist(address(pendleAdapter), true);
        router.transferOwnership(admin);
        vm.stopBroadcast();
    }
}
