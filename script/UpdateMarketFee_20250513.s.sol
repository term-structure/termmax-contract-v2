// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {PendleSwapV3Adapter} from "contracts/router/swapAdapters/PendleSwapV3Adapter.sol";
import {ITermMaxVault} from "contracts/vault/ITermMaxVault.sol";
import {ITermMaxMarket, MarketConfig} from "contracts/ITermMaxMarket.sol";
import {StringHelper} from "./utils/StringHelper.sol";

interface IAccessManager {
    function updateMarketConfig(ITermMaxMarket market, MarketConfig calldata newConfig) external;
}

/// @title update market configs
/// @author evan
/// @notice
contract UpdateMarket is Script {
    // Network-specific config loaded from environment variables
    string network;

    address[] eth_stableCoinMarkets = [
        0x03f2Af12aE4eb5533c3f7773BE826e8da56F6E1a,
        0x1A69127188B72A155165255270017b4c78f31b88,
        0x22Cd4c59eD4bb2ad852892518073056441c55BFE,
        0x2524D9a55C2D18A3F257A7F67AfD552B285de34E,
        0x403863917316Bf8AA1966F9D90b393Cec98F991b,
        0x6f5c8838E618448e43385E4C401006822Aa15142,
        0x7526D036cDDbD3bdFDd8370D75304b822740b291,
        0x988a287c4340B18665cC5E128DC76906A5C839e6,
        0x9904F3b879385033faa31B50d1D63cb80b3495A3,
        0xCE511791715D1A84cD2f7BfA279F92c187bb9d93,
        0xd017E469d22AB7FfB097b9aA329391874954523b,
        0xd699EFC4162d76BfD3cB553D65f850c882C29F5F,
        0xdBB2D44c238c459cCB820De886ABF721EF6E6941,
        0xe867255dC0c3a27c90f756ECC566a5292ce19492,
        0xEd7cD45E5e6ef68261929B58539805bA3c061f14,
        0xf4924D6189552ae5A7818088dA6f23Bd33281C1b,
        0x8d501c7640595EC9D2A39Fbd30dED7672e9631BD,
        0xa1ed39C786eea298925DD6FcC33199C3fF06765E,
        0x37877773B1289c27Bb6159b86613Efd0d15cADaE
    ];
    address[] eth_unstableCoinMarkets = [
        0x0B7eFE5DE3c3B5d75de33e25965b193d6Ba79f52,
        0x484CDece3FC951a7D009b9dBAC66EC287eC1f58e,
        0x918D8Ecba4C683EF3004b1C313cfEF5e3b9E1146,
        0xaBE8ab2223c846466Eb30f5137A7f05106c9d0c4,
        0xb9919eE2169a7dA664AD024C6dDCF0ccD4121C26,
        0xBebB5CEe893110cF477901AF7FA94E4840606421,
        0xc68a2fbD7cb560c71CcAfbDeE971824Ed9bF4556,
        0xC898Fa3A26CEAcAE25cCffF6003B087948dEDE2a,
        0xD316d4494c840F8A758FB6184e9b60281e35cC02,
        0xf0dE37189366F0f3AAe2795160763F3F34797B11
    ];
    address eth_accessManagerAddr = 0xDA4aAF85Bb924B53DCc2DFFa9e1A9C2Ef97aCFDF;

    address[] arb_stableCoinMarkets = [
        0x0b91Cd4e86F0DBBbB2c37c384e1fA91B9a5A3220,
        0x10Af30e205Da0fFc594433BB87e41039be5d1f01,
        0x49E11668EAc15896ecF5B31baeF63C98897D4263,
        0x58C4d4688E0Bc92eF8d81fb963Bca2EaA5DFc31C,
        0x59e3D532727221ac3aeE2D6303cf3C39F1De65D7,
        0x63765e904777E0e13F0cE46A63B2feCf920681aA,
        0x79A4963f8b2f8d997908615352A44192Bc3D23e7,
        0xC62B23864c1e909868471bf72Cc457397BC52E13
    ];
    address[] arb_unstableCoinMarkets = [
        0x2706f663C6e6a0AF2e1c16f7e0d2CcC85758d92c,
        0x4B66219eCcE3AD157A31B9E584beFDc798b556A1,
        0xA016DecA4AbdB8fd94BC221a5feB15BA3DB62031,
        0xa93A81835DAb4AC07649506B88AF7eE6DDaD03Ba,
        0xcc60D097222f45538159D43681FBa4B1fD37DE97
    ];
    address arb_accessManagerAddr = 0xFaD175CAf9B0Ac0EBca3B1816ec799884EB04B9c;

    uint32 ref_stable = 0.06e8;
    uint32 ref_unstable = 0.03e8;
    // uint32 mint_gt_fee_stable = 0.1e8;
    // uint32 mint_gt_fee_unstable = 0.1e8;

    uint256 operatorPrivateKey;
    address operator;

    function setUp() public {
        // Load network from environment variable
        network = vm.envString("NETWORK");
        string memory networkUpper = StringHelper.toUpper(network);

        // Load network-specific configuration
        string memory operatorPrivateKeyPrivateKeyVar = string.concat(networkUpper, "_OPERATOR_PRIVATE_KEY");

        operatorPrivateKey = vm.envUint(operatorPrivateKeyPrivateKeyVar);
        operator = vm.addr(operatorPrivateKey);
    }

    function run() public {
        if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("eth-mainnet"))) {
            updateEth();
        } else if (keccak256(abi.encodePacked(network)) == keccak256(abi.encodePacked("arb-mainnet"))) {
            updateArb();
        }
    }

    function updateArb() internal {
        console.log("=== Configuration ===");
        console.log("Network:", network);
        console.log("Operator:", operator);
        console.log("AccessManager:", arb_accessManagerAddr);
        console.log("");

        console.log("=== Update markets fees ===");

        vm.startBroadcast(operatorPrivateKey);
        IAccessManager accessManager = IAccessManager(arb_accessManagerAddr);

        for (uint256 i = 0; i < arb_stableCoinMarkets.length; i++) {
            address market = arb_stableCoinMarkets[i];
            ITermMaxMarket termMaxMarket = ITermMaxMarket(market);
            MarketConfig memory config = termMaxMarket.config();

            config.feeConfig.mintGtFeeRef = ref_stable;
            // config.feeConfig.mintGtFeeRatio = mint_gt_fee_stable;
            accessManager.updateMarketConfig(termMaxMarket, config);
            config = termMaxMarket.config();
            console.log("market", market);
            console.log("mintGtFeeRef", config.feeConfig.mintGtFeeRef);
        }

        for (uint256 i = 0; i < arb_unstableCoinMarkets.length; i++) {
            address market = arb_unstableCoinMarkets[i];
            ITermMaxMarket termMaxMarket = ITermMaxMarket(market);
            MarketConfig memory config = termMaxMarket.config();

            config.feeConfig.mintGtFeeRef = ref_unstable;
            // config.feeConfig.mintGtFeeRatio = mint_gt_fee_unstable;
            accessManager.updateMarketConfig(termMaxMarket, config);
            config = termMaxMarket.config();
            console.log("market", market);
            console.log("mintGtFeeRef", config.feeConfig.mintGtFeeRef);
        }
        vm.stopBroadcast();
    }

    function updateEth() internal {
        console.log("=== Configuration ===");
        console.log("Network:", network);
        console.log("Operator:", operator);
        console.log("AccessManager:", eth_accessManagerAddr);
        console.log("");

        console.log("=== Update markets fees ===");

        vm.startBroadcast(operatorPrivateKey);
        IAccessManager accessManager = IAccessManager(eth_accessManagerAddr);

        for (uint256 i = 0; i < eth_stableCoinMarkets.length; i++) {
            address market = eth_stableCoinMarkets[i];
            ITermMaxMarket termMaxMarket = ITermMaxMarket(market);
            MarketConfig memory config = termMaxMarket.config();

            config.feeConfig.mintGtFeeRef = ref_stable;
            // config.feeConfig.mintGtFeeRatio = mint_gt_fee_stable;
            accessManager.updateMarketConfig(termMaxMarket, config);
            config = termMaxMarket.config();
            console.log("market", market);
            console.log("mintGtFeeRef", config.feeConfig.mintGtFeeRef);
        }

        for (uint256 i = 0; i < eth_unstableCoinMarkets.length; i++) {
            address market = eth_unstableCoinMarkets[i];
            ITermMaxMarket termMaxMarket = ITermMaxMarket(market);
            MarketConfig memory config = termMaxMarket.config();

            config.feeConfig.mintGtFeeRef = ref_unstable;
            // config.feeConfig.mintGtFeeRatio = mint_gt_fee_unstable;
            accessManager.updateMarketConfig(termMaxMarket, config);
            config = termMaxMarket.config();
            console.log("market", market);
            console.log("mintGtFeeRef", config.feeConfig.mintGtFeeRef);
        }
        vm.stopBroadcast();
    }
}
