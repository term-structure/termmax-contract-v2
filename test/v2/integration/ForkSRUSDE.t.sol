// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";
import {ITermMaxOrder} from "contracts/v1/ITermMaxOrder.sol";
import {
    IGearingToken,
    GearingTokenEvents,
    AbstractGearingToken,
    GtConfig
} from "contracts/v1/tokens/AbstractGearingToken.sol";
import {IOracle} from "contracts/v1/oracle/IOracle.sol";
import {
    ForkBaseTestV2,
    TermMaxFactoryV2,
    MarketConfig,
    IERC20,
    MarketInitialParams,
    IERC20Metadata
} from "test/v2/mainnet-fork/ForkBaseTestV2.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface SRUSDE {
    function redeem(address token, uint256 shares, address receiver, address owner) external returns (uint256);
}

contract ForkSRUSDE is ForkBaseTestV2 {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string DATA_PATH = string.concat(vm.projectRoot(), "/test/testdata/fork/mainnet.json");

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address srUSDE = 0x3d7d6fdf07EE548B939A80edbc9B2256d0cdc003;
    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address susde = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    address admin = vm.randomAddress();

    function _getForkRpcUrl() internal view override returns (string memory) {
        return MAINNET_RPC_URL;
    }

    function _getDataPath() internal view override returns (string memory) {
        return DATA_PATH;
    }

    function _finishSetup() internal override {
        vm.label(usdc, "USDC");
        vm.label(srUSDE, "srUSDE");
        vm.label(usde, "USDE");
        vm.label(susde, "sUSDE");
    }

    function testDepositAndWithraw() public {
        address user = vm.randomAddress();
        deal(user, 10 ether);
        uint8 usdeDecimals = IERC20Metadata(usde).decimals();
        uint256 depositAmount = 10000 * 10 ** usdeDecimals;
        deal(usde, user, depositAmount);
        vm.startPrank(user);
        IERC20(usde).approve(srUSDE, type(uint256).max);
        IERC4626(srUSDE).deposit(depositAmount, user);
        uint256 shares = IERC4626(srUSDE).balanceOf(user);
        console.log("shares received:", shares);
        uint256 withdrawAmount = IERC4626(srUSDE).previewRedeem(shares);
        console.log("withdraw amount:", withdrawAmount);
        SRUSDE(srUSDE).redeem(susde, shares, user, user);
        uint256 finalBalance = IERC20(usde).balanceOf(user);
        console.log("usde balance:", finalBalance);
        console.log("sUSDE balance:", IERC20(susde).balanceOf(user));
        vm.stopPrank();
    }
}
