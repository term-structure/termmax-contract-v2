// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "contracts/TermMaxMarket.sol";
import {MockERC20} from "contracts/test/MockERC20.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "contracts/test/MockPriceFeed.sol";
import {MarketConfig} from "contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {IOracle} from "contracts/oracle/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "contracts/test/MockSwapAdapter.sol";
import {JsonLoader} from "../../utils/JsonLoader.sol";
import {Faucet} from "contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "contracts/test/testnet/FaucetERC20.sol";
import {DeployBase} from "../DeployBase.s.sol";
import {OracleAggregator, AggregatorV3Interface} from "contracts/oracle/OracleAggregator.sol";

contract DeloyMarketFork is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("FORK_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("FORK_ADMIN_ADDRESS");

    // address config
    address factoryAddr = address(0x98f66624BA8b543748e610631487A647819462eA);
    address oracleAddr = address(0xbF23687645bDBC4Fbc164469C3e09650FD72782c);
    address routerAddr = address(0xCe95eEB4B5eCa104845614b0c52827D6595a9bE7);

    function run() public {
        uint256 currentBlockNum = block.number;
        string memory deployDataPath = string.concat(vm.projectRoot(), "/script/deploy/deploydata/fork.json");
        OracleAggregator oracle = OracleAggregator(oracleAddr);
        vm.startBroadcast(deployerPrivateKey);
        (TermMaxMarket[] memory markets, JsonLoader.Config[] memory configs) = deployMarketsMainnet(
            factoryAddr,
            oracleAddr,
            routerAddr,
            deployDataPath,
            adminAddr
        );

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Address Info =====");
        console.log("Deplyer:", deployerAddr);
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");

        for (uint256 i = 0; i < markets.length; i++) {
            console.log("===== Market Info - %d =====", i);
            printMarketConfig(oracle, markets[i], configs[i].salt);
            console.log("");
        }
    }

    function printMarketConfig(OracleAggregator oracle, TermMaxMarket market, uint256 salt) public view {
        MarketConfig memory marketConfig = market.config();
        (IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateralAddr, IERC20 underlying) = market
            .tokens();

        console.log("Market deployed at:", address(market));
        console.log(
            "Collateral (%s) deployed at: %s",
            IERC20Metadata(collateralAddr).symbol(),
            address(collateralAddr)
        );
        console.log(
            "Underlying (%s) deployed at: %s",
            IERC20Metadata(address(underlying)).symbol(),
            address(underlying)
        );
        (
            AggregatorV3Interface collateralAggregator,
            AggregatorV3Interface collateralBackupAggregator,
            uint32 collateralHeartbeat
        ) = oracle.oracles(collateralAddr);

        (
            AggregatorV3Interface underlyingAggregator,
            AggregatorV3Interface underlyingBackupAggregator,
            uint32 underlyingHeartbeat
        ) = oracle.oracles(address(underlying));
        console.log("Collateral price feed deployed at:", address(collateralAggregator));
        console.log("Underlying price feed deployed at:", address(underlyingAggregator));

        console.log("FT deployed at:", address(ft));
        console.log("XT deployed at:", address(xt));
        console.log("GT deployed at:", address(gt));

        console.log();

        console.log("Treasurer:", marketConfig.treasurer);
        console.log("Maturity:", marketConfig.maturity);
        console.log("Salt:", salt);
        console.log("Lend Taker Fee Ratio:", marketConfig.feeConfig.lendTakerFeeRatio);
        console.log("Lend Maker Fee Ratio:", marketConfig.feeConfig.lendMakerFeeRatio);
        console.log("Borrow Taker Fee Ratio:", marketConfig.feeConfig.borrowTakerFeeRatio);
        console.log("Borrow Maker Fee Ratio:", marketConfig.feeConfig.borrowMakerFeeRatio);
        console.log("Issue FT Fee Ratio:", marketConfig.feeConfig.issueFtFeeRatio);
        console.log("Issue FT Fee Ref:", marketConfig.feeConfig.issueFtFeeRef);
        console.log("Redeem FT Fee Ratio:", marketConfig.feeConfig.redeemFeeRatio);
    }
}
