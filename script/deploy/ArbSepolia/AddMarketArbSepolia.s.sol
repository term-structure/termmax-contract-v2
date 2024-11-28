// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../../contracts/core/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../../contracts/core/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../../contracts/core/TermMaxMarket.sol";
import {MockERC20} from "../../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../../../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken, AggregatorV3Interface} from "../../../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../../contracts/test/MockSwapAdapter.sol";
import {JSONLoader} from "../../utils/JSONLoader.sol";

contract DeployArbSepolia is Script {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");

    // market config
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");

    function run() public {
        string memory deployData = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/deploydata/testData.json"
            )
        );
        JSONLoader.run(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/deploydata/deployData.json"
            )
        );
        // JSONLoader.getConfigFromJson(deployData);

        //     config.marketConfig.openTime = uint64(block.timestamp + 60);

        //     vm.startBroadcast(deployerPrivateKey);

        //     // deploy factory
        //     TermMaxFactory factory = new TermMaxFactory(adminAddr);
        //     TermMaxMarket marketImpl = new TermMaxMarket();
        //     factory.initMarketImplement(address(marketImpl));

        //     // deploy router
        //     address routerImpl = address(new TermMaxRouter());
        //     bytes memory data = abi.encodeCall(TermMaxRouter.initialize, adminAddr);
        //     address proxy = address(new ERC1967Proxy(routerImpl, data));
        //     TermMaxRouter router = TermMaxRouter(proxy);
        //     router.togglePause(false);

        //     // deploy swap adapter
        //     MockSwapAdapter swapAdapter = new MockSwapAdapter(vm.randomAddress());
        //     router.setAdapterWhitelist(address(swapAdapter), true);

        //     // deploy underlying & collateral

        //     MockERC20 collateral = new MockERC20(
        //         config.collateralConfig.name,
        //         config.collateralConfig.symbol,
        //         config.collateralConfig.decimals
        //     );
        //     MockPriceFeed collateralPriceFeed = new MockPriceFeed(adminAddr);
        //     collateralPriceFeed.updateRoundData(
        //         MockPriceFeed.RoundData({
        //             roundId: 1,
        //             answer: config.collateralConfig.initialPrice,
        //             startedAt: block.timestamp,
        //             updatedAt: block.timestamp,
        //             answeredInRound: 1
        //         })
        //     );

        //     MockERC20 underlying = new MockERC20(
        //         config.underlyingConfig.name,
        //         config.underlyingConfig.symbol,
        //         config.underlyingConfig.decimals
        //     );
        //     MockPriceFeed underlingPriceFeed = new MockPriceFeed(adminAddr);
        //     underlingPriceFeed.updateRoundData(
        //         MockPriceFeed.RoundData({
        //             roundId: 1,
        //             answer: config.underlyingConfig.initialPrice,
        //             startedAt: block.timestamp,
        //             updatedAt: block.timestamp,
        //             answeredInRound: 1
        //         })
        //     );

        //     // deploy market
        //     ITermMaxFactory.DeployParams memory params = ITermMaxFactory
        //         .DeployParams({
        //             gtKey: GT_ERC20,
        //             admin: adminAddr,
        //             collateral: address(collateral),
        //             underlying: IERC20Metadata(address(underlying)),
        //             underlyingOracle: AggregatorV3Interface(
        //                 address(underlingPriceFeed)
        //             ),
        //             liquidationLtv: config.liquidationLtv,
        //             maxLtv: config.maxLtv,
        //             liquidatable: config.liquidatable,
        //             marketConfig: config.marketConfig,
        //             gtInitalParams: abi.encode(address(collateralPriceFeed))
        //         });
        //     TermMaxMarket market = TermMaxMarket(factory.createMarket(params));

        //     router.setMarketWhitelist(address(market), true);
        //     vm.stopBroadcast();

        //     MarketConfig memory marketConfig = market.config();

        //     (
        //         IMintableERC20 ft,
        //         IMintableERC20 xt,
        //         IMintableERC20 lpFt,
        //         IMintableERC20 lpXt,
        //         IGearingToken gt,
        //         ,

        //     ) = market.tokens();

        //     console.log("===== Deployment Info =====");
        //     console.log("Deplyer:", adminAddr);
        //     console.log("Factory deployed at:", address(factory));
        //     console.log("Router deployed at:", address(router));
        //     console.log("MockSwapAdapter deployed at:", address(swapAdapter));
        //     console.log("Market deployed at:", address(market));
        //     console.log(
        //         "Collateral (%s) deployed at: %s",
        //         IERC20Metadata(collateral).symbol(),
        //         address(collateral)
        //     );
        //     console.log(
        //         "Collateral price feed deployed at:",
        //         address(collateralPriceFeed)
        //     );
        //     console.log(
        //         "Underlying (%s) deployed at: %s",
        //         IERC20Metadata(address(underlying)).symbol(),
        //         address(underlying)
        //     );
        //     console.log(
        //         "Underlying price feed deployed at:",
        //         address(underlingPriceFeed)
        //     );
        //     console.log("FT deployed at:", address(ft));
        //     console.log("XT deployed at:", address(xt));
        //     console.log("LPFT deployed at:", address(lpFt));
        //     console.log("LPXT deployed at:", address(lpXt));
        //     console.log("GT deployed at:", address(gt));

        //     console.log("===== Market Info =====");
        //     console.log("Treasurer:", marketConfig.treasurer);
        //     console.log("Maturity:", marketConfig.maturity);
        //     console.log("Open Time:", marketConfig.openTime);
        //     console.log("Initial APR:", marketConfig.apr);
        //     console.log("Liquidity Scaling Factor:", marketConfig.lsf);
        //     console.log("Lending Fee Ratio:", marketConfig.lendFeeRatio);
        //     console.log(
        //         "Min Notional Lending Fee Ratio:",
        //         marketConfig.minNLendFeeR
        //     );
        //     console.log("Borrowing Fee Ratio:", marketConfig.borrowFeeRatio);
        //     console.log(
        //         "Min Notional Borrowing Fee Ratio:",
        //         marketConfig.minNBorrowFeeR
        //     );
        //     console.log("Redeem Fee Ratio:", marketConfig.redeemFeeRatio);
        //     console.log("Issue FT Fee Ratio:", marketConfig.issueFtFeeRatio);
        //     console.log("Protocol Fee Ratio:", marketConfig.protocolFeeRatio);
        //     console.log("Locking Percentage:", marketConfig.lockingPercentage);
        //     console.log("Initial LTV:", marketConfig.initialLtv);
        //     console.log("Reward Is Distributed:", marketConfig.rewardIsDistributed);
    }
}
