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
import {SwapAdapter} from "../../../contracts/test/testnet/SwapAdapter.sol";
import {JSONLoader} from "../../../test/utils/JSONLoader.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../../contracts/test/testnet/FaucetERC20.sol";

contract DeployArbSepolia is Script {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
    // uint256 deployerPrivateKey =
    //     0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("ARB_SEPOLIA_ADMIN_ADDRESS");
    // address adminAddr = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    address priceFeedOperatorAddr =
        vm.envAddress("ARB_SEPOLIA_PRICE_FEED_OPERATOR_ADDRESS");
    // address priceFeedOperatorAddr = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;

    // market config
    bytes32 constant GT_ERC20 = keccak256("GearingTokenWithERC20");
    MarketConfig marketConfig =
        MarketConfig({
            treasurer: 0x944a0Af591E2C23a2E81fe4c10Bd9c47Cf866F4b,
            maturity: 1743120000,
            openTime: uint64(vm.getBlockTimestamp() + 60),
            apr: 12000000,
            lsf: 80000000,
            lendFeeRatio: 3000000,
            minNLendFeeR: 100000,
            borrowFeeRatio: 3000000,
            minNBorrowFeeR: 100000,
            redeemFeeRatio: 50000000,
            issueFtFeeRatio: 10000000,
            lockingPercentage: 50000000,
            initialLtv: 88000000,
            protocolFeeRatio: 50000000,
            rewardIsDistributed: true
        });
    uint32 maxLtv = 0.89e8;
    uint32 liquidationLtv = 0.9e8;

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // deploy factory
        TermMaxFactory factory = new TermMaxFactory(adminAddr);

        TermMaxMarket marketImpl = new TermMaxMarket();

        factory.initMarketImplement(address(marketImpl));

        // deploy router
        address routerImpl = address(new TermMaxRouter());

        bytes memory data = abi.encodeCall(TermMaxRouter.initialize, adminAddr);
        address proxy = address(new ERC1967Proxy(routerImpl, data));

        TermMaxRouter router = TermMaxRouter(proxy);
        router.togglePause(false);

        // deploy swap adapter
        SwapAdapter swapAdapter = new SwapAdapter(vm.randomAddress());

        router.setAdapterWhitelist(address(swapAdapter), true);

        Faucet faucet = new Faucet(adminAddr);

        // deploy underlying & collateral
        (FaucetERC20 pt, MockPriceFeed ptPriceFeed) = faucet.addToken(
            "PT Ethena sUSDE 27MAR2025",
            "PT-sUSDE-27MAR2025",
            18,
            1000e18
        );

        ptPriceFeed.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: 95e6,
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );

        (FaucetERC20 usdc, MockPriceFeed usdcPriceFeed) = faucet.addToken(
            "USD Coin",
            "USDC",
            6,
            1000e6
        );

        usdcPriceFeed.updateRoundData(
            MockPriceFeed.RoundData({
                roundId: 1,
                answer: 1e8,
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );

        ptPriceFeed.transferOwnership(priceFeedOperatorAddr);

        usdcPriceFeed.transferOwnership(priceFeedOperatorAddr);

        // deploy market
        ITermMaxFactory.DeployParams memory params = ITermMaxFactory
            .DeployParams({
                gtKey: GT_ERC20,
                admin: adminAddr,
                collateral: address(pt),
                underlying: IERC20Metadata(address(usdc)),
                underlyingOracle: AggregatorV3Interface(address(usdcPriceFeed)),
                liquidationLtv: liquidationLtv,
                maxLtv: maxLtv,
                liquidatable: true,
                marketConfig: marketConfig,
                gtInitalParams: abi.encode(address(ptPriceFeed))
            });
        TermMaxMarket market = TermMaxMarket(factory.createMarket(params));

        router.setMarketWhitelist(address(market), true);

        vm.stopBroadcast();

        MarketConfig memory config = market.config();
        (
            IMintableERC20 ft,
            IMintableERC20 xt,
            IMintableERC20 lpFt,
            IMintableERC20 lpXt,
            IGearingToken gt,
            address collateral,
            IERC20 underlying
        ) = market.tokens();

        console.log("===== Deployment Info =====");
        console.log("Deplyer:", adminAddr);
        console.log("Price Feed Operator:", priceFeedOperatorAddr);
        console.log("Faucet deployed at:", address(faucet));
        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));
        console.log("SwapAdapter deployed at:", address(swapAdapter));
        console.log("Market deployed at:", address(market));
        console.log(
            "Collateral (%s) deployed at: %s",
            IERC20Metadata(collateral).symbol(),
            address(collateral)
        );
        console.log("Collateral price feed deployed at:", address(ptPriceFeed));
        console.log(
            "Underlying (%s) deployed at: %s",
            IERC20Metadata(address(underlying)).symbol(),
            address(underlying)
        );
        console.log(
            "Underlying price feed deployed at:",
            address(usdcPriceFeed)
        );
        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("LPFT deployed at:", address(lpFt));
        console.log("LPXT deployed at:", address(lpXt));
        console.log("GT deployed at:", address(gt));

        console.log("===== Market Info =====");
        console.log("Treasurer:", config.treasurer);
        console.log("Maturity:", config.maturity);
        console.log("Open Time:", config.openTime);
        console.log("Initial APR:", config.apr);
        console.log("Liquidity Scaling Factor:", config.lsf);
        console.log("Lending Fee Ratio:", config.lendFeeRatio);
        console.log("Min Notional Lending Fee Ratio:", config.minNLendFeeR);
        console.log("Borrowing Fee Ratio:", config.borrowFeeRatio);
        console.log("Min Notional Borrowing Fee Ratio:", config.minNBorrowFeeR);
        console.log("Redeem Fee Ratio:", config.redeemFeeRatio);
        console.log("Issue FT Fee Ratio:", config.issueFtFeeRatio);
        console.log("Protocol Fee Ratio:", config.protocolFeeRatio);
        console.log("Locking Percentage:", config.lockingPercentage);
        console.log("Initial LTV:", config.initialLtv);
        console.log("Reward Is Distributed:", config.rewardIsDistributed);
    }
}
