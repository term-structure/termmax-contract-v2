// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TermMaxFactory} from "../../../contracts/factory/TermMaxFactory.sol";
import {ITermMaxFactory} from "../../../contracts/factory/ITermMaxFactory.sol";
import {TermMaxRouter} from "../../../contracts/router/TermMaxRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TermMaxMarket} from "../../../contracts/TermMaxMarket.sol";
import {TermMaxOrder, ISwapCallback} from "../../../contracts/TermMaxOrder.sol";
import {ITermMaxOrder} from "../../../contracts/TermMaxOrder.sol";
import {MockERC20} from "../../../contracts/test/MockERC20.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MockPriceFeed} from "../../../contracts/test/MockPriceFeed.sol";
import {MarketConfig, OrderConfig, CurveCuts, CurveCut} from "../../../contracts/storage/TermMaxStorage.sol";
import {IMintableERC20} from "../../../contracts/tokens/IMintableERC20.sol";
import {IGearingToken} from "../../../contracts/tokens/IGearingToken.sol";
import {IOracle} from "../../../contracts/oracle/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockSwapAdapter} from "../../../contracts/test/MockSwapAdapter.sol";
import {JsonLoader} from "../../utils/JsonLoader.sol";
import {Faucet} from "../../../contracts/test/testnet/Faucet.sol";
import {FaucetERC20} from "../../../contracts/test/testnet/FaucetERC20.sol";
import {DeployBase} from "../DeployBase.s.sol";

contract DeloyOrderHolesky is DeployBase {
    // admin config
    uint256 deployerPrivateKey = vm.envUint("HOLESKY_DEPLOYER_PRIVATE_KEY");
    address deployerAddr = vm.addr(deployerPrivateKey);
    address adminAddr = vm.envAddress("HOLESKY_ADMIN_ADDRESS");
    address priceFeedOperatorAddr = vm.envAddress("HOLESKY_PRICE_FEED_OPERATOR_ADDRESS");

    // address config
    address marketAddr = address(0x0D5168Ae17e62B42ed85DD8Cc35DA7913Ec41dd6);

    function run() public {
        uint256 currentBlockNum = block.number;
        TermMaxMarket market = TermMaxMarket(marketAddr);
        vm.startBroadcast(deployerPrivateKey);
        uint256 maxXtReserve = 1000000000000000000000000000000000000000000000000000000;
        CurveCut memory curveCut0 = CurveCut({xtReserve: 0, liqSquare: 461683991532123193344, offset: 33973665961});
        CurveCut memory curveCut1 = CurveCut({
            xtReserve: 9000000000,
            liqSquare: 259820550347600396288,
            offset: 23237900077
        });
        CurveCut memory curveCut2 = CurveCut({
            xtReserve: 21000000000,
            liqSquare: 605605556075689803776,
            offset: 46538697296
        });
        CurveCut[] memory _curveCuts = new CurveCut[](3);
        _curveCuts[0] = curveCut0;
        _curveCuts[1] = curveCut1;
        _curveCuts[2] = curveCut2;
        CurveCuts memory curveCuts = CurveCuts({lendCurveCuts: _curveCuts, borrowCurveCuts: _curveCuts});
        ITermMaxOrder order = market.createOrder(deployerAddr, maxXtReserve, ISwapCallback(address(0)), curveCuts);

        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Order Info =====");
        console.log("Order Maker:", deployerAddr);
        console.log("Order Address:", address(order));
        console.log("Deployed at block number:", currentBlockNum);
        console.log("");
    }
}
