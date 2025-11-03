// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";
import {UniversalFactory} from "contracts/v2/tokenomics/UniversalFactory.sol";
import {TMX} from "contracts/v2/tokenomics/TMX.sol";

contract DeployTMX is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    address tmxAdmin = 0x65B7949C97e7d96bCd81cf53BfF602923973c950;
    address factoryAddress = 0x1CD8b9427D1A419015Ae659cB04bd897fA4642fD;
    bool isBroadcast;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        isBroadcast = vm.envBool("IS_BROADCAST");
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);

        coreParams.isMainnet = vm.envBool("IS_MAINNET");
        coreParams.isL2Network = vm.envBool("IS_L2");
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        UniversalFactory factory = UniversalFactory(factoryAddress);
        bytes memory creationCode = abi.encodePacked(
            type(TMX).creationCode,
            abi.encode(tmxAdmin)
        );
        uint256 nonce = 550000000015519333;
        address predictAddress = factory.predictAddress(creationCode, nonce);
        address deployedAddress = factory.deploy(creationCode, nonce);
        console.log("Predicted TMX address:", predictAddress);
        console.log("Deployed TMX at:", deployedAddress);
        assert(predictAddress == deployedAddress);
        uint256 totalSupply = TMX(deployedAddress).totalSupply();
        assert(totalSupply == 1e9 ether);
        uint256 balanceOfAdmin = TMX(deployedAddress).balanceOf(tmxAdmin);
        assert(balanceOfAdmin == totalSupply);
        vm.stopBroadcast();

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log();

        console.log("===== Core Info =====");
        console.log("Deployer:", coreParams.deployerAddr);
        console.log("Admin:", adminAddr);

        string memory deploymentEnv = string(
            abi.encodePacked(
                "NETWORK=",
                coreParams.network,
                "\nDEPLOYED_AT=",
                vm.toString(block.timestamp),
                "\nGIT_BRANCH=",
                getGitBranch(),
                "\nGIT_COMMIT_HASH=",
                vm.toString(getGitCommitHash()),
                "\nBLOCK_NUMBER=",
                vm.toString(block.number),
                "\nBLOCK_TIMESTAMP=",
                vm.toString(block.timestamp),
                "\nDEPLOYER_ADDRESS=",
                vm.toString(vm.addr(deployerPrivateKey)),
                "\nADMIN_ADDRESS=",
                vm.toString(adminAddr)
            )
        );
        deploymentEnv = string(
            abi.encodePacked(
                deploymentEnv,
                "\nTMX_ADDRESS=",
                vm.toString(deployedAddress)
            )
        );

        string memory path = string.concat(
            vm.projectRoot(),
            "/deployments/",
            coreParams.network,
            "/",
            coreParams.network,
            "-TMX-",
            vm.toString(block.timestamp),
            ".env"
        );
        if (isBroadcast) {
            vm.writeFile(path, deploymentEnv);
        }
    }
}
