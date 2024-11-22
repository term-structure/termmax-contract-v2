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
import {MockPriceFeed} from "../contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "../contracts/core/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../contracts/core/tokens/IMintableERC20.sol";
import {IGearingToken, AggregatorV3Interface} from "../contracts/core/tokens/IGearingToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeployUtils} from "./Utils.sol";

contract DeployArbSepolia is Script {
    // deployer config
    uint256 deployerPrivateKey = vm.envUint("ARB_SEPOLIA_DEPLOYER_PRIVATE_KEY");
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

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TermMaxFactory factory = DeployUtils.deployFactory(deployerAddr);
        TermMaxRouter router = DeployUtils.deployRouter(deployerAddr);
        MockERC20 pt = DeployUtils.deployMockERC20(
            deployerAddr,
            "PT-sUSDe-27MAR2025",
            "PT",
            18
        );
        MockPriceFeed ptPriceFeed = DeployUtils.deployMockPriceFeed(
            deployerAddr,
            95e6
        );
        MockERC20 usdc = DeployUtils.deployMockERC20(
            deployerAddr,
            "USDC",
            "USDC",
            6
        );
        MockPriceFeed usdcPriceFeed = DeployUtils.deployMockPriceFeed(
            deployerAddr,
            1e8
        );

        TermMaxMarket market = DeployUtils.deployMarket(
            deployerAddr,
            address(factory),
            address(pt),
            address(ptPriceFeed),
            address(usdc),
            address(usdcPriceFeed),
            GT_ERC20,
            liquidationLtv,
            maxLtv,
            marketConfig
        );

        DeployUtils.whitelistMarket(address(router), address(market));
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
        console.log("Deplyer:", deployerAddr);
        console.log("Factory deployed at:", address(factory));
        console.log("Router deployed at:", address(router));
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
