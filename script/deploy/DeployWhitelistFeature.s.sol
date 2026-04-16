// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./DeployBaseV2.s.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OrderConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {JsonLoader} from "script/utils/JsonLoader.sol";
import {OrderV2ConfigurationParams} from "contracts/v2/vault/VaultStorageV2.sol";
import {ITermMaxOrderV2} from "contracts/v2/ITermMaxOrderV2.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {StakingBuffer} from "contracts/v2/tokens/StakingBuffer.sol";
import {SimpleAggregator} from "contracts/v2/oracle/SimpleAggregator.sol";
import {StringHelper} from "script/utils/StringHelper.sol";
import {ITermMaxMarket} from "contracts/v1/ITermMaxMarket.sol";

contract DeployWhitelistFeature is DeployBaseV2 {
    using StringHelper for string;
    // Network-specific config loaded from environment variables

    uint256 deployerPrivateKey;

    CoreParams coreParams;
    DeployedContracts coreContracts;
    bool isBroadcast;

    address aavePool;
    uint16 aaveReferralCode;

    bool isEth;
    bool isArb;
    bool isBnb;
    bool isBera;
    bool isHyper;
    bool isXlayer;
    bool isBase;
    bool isB2;
    bool isPharos;

    address automaticDeployer = vm.envAddress("AUTOMATIC_DEPLOYER_ADDRESS");
    address interestManager = vm.envAddress("INTEREST_MANAGER_ADDRESS");

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        isBroadcast = vm.envBool("IS_BROADCAST");
        string memory networkUpper = toUpper(coreParams.network);
        _getNetWork();

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");
        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        coreParams.adminAddr = vm.envAddress(adminVar);

        aavePool = vm.envAddress(string.concat(networkUpper, "_AAVE_POOL"));
        aaveReferralCode = uint16(vm.envUint(string.concat(networkUpper, "_AAVE_REFERRAL_CODE")));
        coreParams.isMainnet = vm.envBool("IS_MAINNET");
        coreParams.isL2Network = vm.envBool("IS_L2");
        {
            // Create deployments directory if it doesn't exist
            string memory deploymentsDir = string.concat(vm.projectRoot(), "/deployments/", coreParams.network);
            if (!vm.exists(deploymentsDir)) {
                // Directory doesn't exist, create it
                vm.createDir(deploymentsDir, true);
            }
        }

        string memory deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-access-manager.json"
        );
        string memory json = vm.readFile(deploymentPath);
        address accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );
        if (vm.exists(deploymentPath)) {
            json = vm.readFile(deploymentPath);
            coreContracts = readDeployData(json);
        }
        console.log("Using existing AccessManagerV2 at:", accessManagerAddr);
        coreContracts.accessManager = AccessManagerV2(accessManagerAddr);
        console.log("Using existing WhitelistManager at:", address(coreContracts.whitelistManager));
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        // upgrade contracts
        console.log("Upgrading contracts to latest versions...");
        console.log("Upgrade AccessManager implementation to latest version");
        address newAccessManagerImpl = address(new AccessManagerV2());
        console.log("Deployed new AccessManager implementation at:", newAccessManagerImpl);
        // log upgrade tx calldata for AccessManager used in safe wallet transaction
        bytes memory accessManagerUpgradeCalldata =
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, newAccessManagerImpl, "");
        console.log("AccessManager upgrade calldata:");
        console.logBytes(accessManagerUpgradeCalldata);

        console.log("Upgrade WhitelistManager implementation to latest version");
        address newWhitelistManagerImpl = address(new WhitelistManager(address(coreContracts.accessManager)));
        console.log("Deployed new WhitelistManager implementation at:", newWhitelistManagerImpl);
        coreContracts.accessManager.upgradeSubContract(coreContracts.whitelistManager, newWhitelistManagerImpl, "");

        console.log("Upgrade TermMaxRouterV1 implementation to latest version");
        address newTermMaxRouterV1Impl = address(new TermMaxRouter_V1_1_2(address(coreContracts.accessManager)));
        console.log("Deployed new TermMaxRouterV1 implementation at:", newTermMaxRouterV1Impl);
        coreContracts.accessManager.upgradeSubContract(coreContracts.routerV1, newTermMaxRouterV1Impl, "");

        console.log("Upgrade TermMaxRouterV2 implementation to latest version");
        address newTermMaxRouterV2Impl = address(new TermMaxRouterV2(address(coreContracts.accessManager)));
        console.log("Deployed new TermMaxRouterV2 implementation at:", newTermMaxRouterV2Impl);
        coreContracts.accessManager.upgradeSubContract(coreContracts.router, newTermMaxRouterV2Impl, "");

        console.log("Upgrade MakerHelper implementation to latest version");
        address newMakerHelperImpl = address(new MakerHelper(address(coreContracts.whitelistManager)));
        console.log("Deployed new MakerHelper implementation at:", newMakerHelperImpl);
        coreContracts.accessManager.upgradeSubContract(coreContracts.makerHelper, newMakerHelperImpl, "");

        // new market factory
        if (isBnb) {
            (coreContracts.factory, coreContracts.alphaFactory) =
                deployMarketFactories(address(coreContracts.accessManager), address(coreContracts.whitelistManager));
            console.log("Deployed new TermMaxMarketFactory at:", address(coreContracts.factory));
            console.log("Deployed new TermMaxAlphaFactory at:", address(coreContracts.alphaFactory));
        } else {
            coreContracts.factory =
                deployFactory(address(coreContracts.accessManager), address(coreContracts.whitelistManager));
            console.log("Deployed new TermMaxMarketFactory at:", address(coreContracts.factory));
        }

        // new vault factory
        coreContracts.vaultFactory =
            deployVaultFactory(address(coreContracts.accessManager), address(coreContracts.whitelistManager));
        console.log("Deployed new TermMaxVaultFactory at:", address(coreContracts.vaultFactory));

        // new 4626 factory

        address stableERC4626For4626Implementation;
        address stableERC4626ForAaveImplementation;
        address variableERC4626ForAaveImplementation;
        address stableERC4626ForVenusImplementation;
        address stableERC4626ForCustomizeImplementation;
        {
            // read existing implementations from core-v2 deployment if exist, otherwise deploy new ones
            stableERC4626For4626Implementation = coreContracts.tmx4626Factory.stableERC4626For4626Implementation();
            stableERC4626ForAaveImplementation = coreContracts.tmx4626Factory.stableERC4626ForAaveImplementation();
            variableERC4626ForAaveImplementation = coreContracts.tmx4626Factory.variableERC4626ForAaveImplementation();
            try coreContracts.tmx4626Factory.stableERC4626ForVenusImplementation() returns (address addr) {
                stableERC4626ForVenusImplementation = addr;
            } catch {
                console.log("Ignoring missing TERMMAX_4626_FOR_VENUS_IMPLEMENTATION");
            }
            try coreContracts.tmx4626Factory.stableERC4626ForCustomizeImplementation() returns (address addr) {
                stableERC4626ForCustomizeImplementation = addr;
            } catch {
                stableERC4626ForCustomizeImplementation = address(new StableERC4626ForCustomize());
                console.log(
                    "Deploying new StableERC4626ForCustomize implementation at:",
                    stableERC4626ForCustomizeImplementation
                );
            }
        }

        coreContracts.tmx4626Factory = new TermMax4626Factory(
            address(coreContracts.accessManager),
            stableERC4626For4626Implementation,
            stableERC4626ForAaveImplementation,
            stableERC4626ForVenusImplementation,
            variableERC4626ForAaveImplementation,
            stableERC4626ForCustomizeImplementation,
            address(coreContracts.whitelistManager)
        );
        console.log("Deployed TermMax4626Factory at:", address(coreContracts.tmx4626Factory));
        vm.stopBroadcast();

        uint256 whitelistFactoryCount = 3;
        if (address(coreContracts.alphaFactory) != address(0)) {
            whitelistFactoryCount++;
        }
        uint256 grantCount = whitelistFactoryCount + 4;
        bytes32[] memory roles = new bytes32[](grantCount);
        address[] memory grantees = new address[](grantCount);

        uint256 i;
        roles[i] = coreContracts.accessManager.WHITELIST_ROLE();
        grantees[i] = address(coreContracts.factory);
        unchecked {
            ++i;
        }

        if (address(coreContracts.alphaFactory) != address(0)) {
            roles[i] = coreContracts.accessManager.WHITELIST_ROLE();
            grantees[i] = address(coreContracts.alphaFactory);
            unchecked {
                ++i;
            }
        }

        roles[i] = coreContracts.accessManager.WHITELIST_ROLE();
        grantees[i] = address(coreContracts.vaultFactory);
        unchecked {
            ++i;
        }

        roles[i] = coreContracts.accessManager.WHITELIST_ROLE();
        grantees[i] = address(coreContracts.tmx4626Factory);
        unchecked {
            ++i;
        }

        roles[i] = coreContracts.accessManager.VAULT_DEPLOYER_ROLE();
        grantees[i] = automaticDeployer;
        unchecked {
            ++i;
        }

        roles[i] = coreContracts.accessManager.POOL_DEPLOYER_ROLE();
        grantees[i] = automaticDeployer;
        unchecked {
            ++i;
        }

        roles[i] = coreContracts.accessManager.STABLE_ERC4626_BUFFER_ROLE();
        grantees[i] = automaticDeployer;
        unchecked {
            ++i;
        }

        roles[i] = coreContracts.accessManager.STABLE_ERC4626_INCOME_WITHDRAW_ROLE();
        grantees[i] = interestManager;

        console.log("Granting roles via safe wallet...");
        for (uint256 j = 0; j < grantCount; ++j) {
            bytes memory grantRoleCalldata =
                abi.encodeWithSelector(coreContracts.accessManager.grantRole.selector, roles[j], grantees[j]);
            console.log("grantRole to:", grantees[j]);
            console.log("role:");
            console.logBytes32(roles[j]);
            console.log("grantee:", grantees[j]);
            console.log("grantRole calldata:");
            console.logBytes(grantRoleCalldata);
        }

        console.log("===== Git Info =====");
        console.log("Git branch:", getGitBranch());
        console.log("Git commit hash:");
        console.logBytes(getGitCommitHash());
        console.log();

        console.log("===== Block Info =====");
        console.log("Block number:", block.number);
        console.log("Block timestamp:", block.timestamp);
        console.log();

        writeAsJson(
            string.concat(
                vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
            ),
            coreParams,
            coreContracts
        );
    }

    function _getNetWork() internal {
        isEth = keccak256(bytes(coreParams.network)) == keccak256(bytes("eth-mainnet"));
        isArb = keccak256(bytes(coreParams.network)) == keccak256(bytes("arb-mainnet"));
        isBnb = keccak256(bytes(coreParams.network)) == keccak256(bytes("bnb-mainnet"));
        isBera = keccak256(bytes(coreParams.network)) == keccak256(bytes("bera-mainnet"));
        isHyper = keccak256(bytes(coreParams.network)) == keccak256(bytes("hyperevm-mainnet"));
        isXlayer = keccak256(bytes(coreParams.network)) == keccak256(bytes("xlayer-mainnet"));
        isBase = keccak256(bytes(coreParams.network)) == keccak256(bytes("base-mainnet"));
        isB2 = keccak256(bytes(coreParams.network)) == keccak256(bytes("b2-mainnet"));
        isPharos = keccak256(bytes(coreParams.network)) == keccak256(bytes("pharos-mainnet"));
    }
}
