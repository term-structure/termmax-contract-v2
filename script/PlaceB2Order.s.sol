// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./deploy/DeployBaseV2.s.sol";
import {DelegateAble} from "contracts/v2/lib/DelegateAble.sol";
import {CurveCuts, CurveCut, OrderConfig} from "contracts/v1/storage/TermMaxStorage.sol";
import {ITermMaxMarketV2} from "contracts/v2/ITermMaxMarketV2.sol";
import {ITermMaxOrder, ITermMaxMarket} from "contracts/v1/ITermMaxOrder.sol";
import {IGearingToken} from "contracts/v1/tokens/IGearingToken.sol";

interface IWBTC {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract PlaceOrder is DeployBaseV2 {
    uint256 deployerPrivateKey;
    address adminAddr;
    address accessManagerAddr;

    CoreParams coreParams;
    DeployedContracts coreContracts;

    function setUp() public {
        // Load network from environment variable
        coreParams.network = vm.envString("NETWORK");
        string memory networkUpper = toUpper(coreParams.network);

        // Load network-specific configuration
        string memory privateKeyVar = string.concat(networkUpper, "_DEPLOYER_PRIVATE_KEY");
        string memory adminVar = string.concat(networkUpper, "_ADMIN_ADDRESS");

        deployerPrivateKey = vm.envUint(privateKeyVar);
        coreParams.deployerAddr = vm.addr(deployerPrivateKey);
        adminAddr = vm.envAddress(adminVar);

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
        accessManagerAddr = vm.parseJsonAddress(json, ".contracts.accessManager");

        deploymentPath = string.concat(
            vm.projectRoot(), "/deployments/", coreParams.network, "/", coreParams.network, "-core-v2.json"
        );
        if (vm.exists(deploymentPath)) {
            json = vm.readFile(deploymentPath);
            coreContracts = readDeployData(json);
        }
        console.log("Using existing AccessManagerV2 at:", accessManagerAddr);
        coreContracts.accessManager = AccessManagerV2(accessManagerAddr);
    }

    uint256 salt = 0;
    uint256 collateralToMintGt = 0.0001e18;
    uint256 debtTokenToDeposit = 0;
    uint128 ftToDeposit = 0;
    uint128 xtToDeposit = 0;
    address marketAddr = 0x5022B6563f6bc9f0D47F407ba32B64e1f438213a;
    IWBTC wbtc = IWBTC(0x4200000000000000000000000000000000000006);
    IERC20 uBTC = IERC20(0x796e4D53067FF374B89b2Ac101ce0c1f72ccaAc2);
    address gt = 0xDfB3959DAD26dFce3E9646c92b086E7fe4D12793;

    function exe() internal {
        uBTC.approve(address(coreContracts.makerHelper), collateralToMintGt);
        OrderInitialParams memory initialParams;

        initialParams.maker = coreParams.deployerAddr;
        initialParams.virtualXtReserve = 0;
        initialParams.orderConfig.maxXtReserve = 1e18;
        initialParams.orderConfig.curveCuts.borrowCurveCuts = new CurveCut[](1);
        initialParams.orderConfig.curveCuts.borrowCurveCuts[0] = CurveCut({
            liqSquare: 40000060000017500001000000000000000000000,
            xtReserve: 0,
            offset: 2000000499999875000100
        });

        DelegateAble.DelegateParameters memory delegateParams;
        address orderAddr = ITermMaxMarketV2(marketAddr).predictOrderAddress(initialParams, salt);
        console.log("Predicted order address:", orderAddr);
        delegateParams = DelegateAble.DelegateParameters({
            delegator: coreParams.deployerAddr,
            delegatee: orderAddr,
            isDelegate: true,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        DelegateAble.Signature memory delegateSignature = generateSignature(
            DelegateAble(gt), // placeholder, will be replaced in the function call
            deployerPrivateKey,
            delegateParams
        );

        (ITermMaxOrder order, uint256 gtId) = coreContracts.makerHelper.placeOrderForV2(
            ITermMaxMarket(marketAddr),
            salt,
            collateralToMintGt,
            debtTokenToDeposit,
            ftToDeposit,
            xtToDeposit,
            initialParams,
            delegateParams,
            delegateSignature
        );
        console.log("Order created at address:", address(order));
        console.log("Minted GT ID:", gtId);
    }

    function run() public {
        console.log("Network:", coreParams.network);
        console.log("Deployer balance:", coreParams.deployerAddr.balance);

        vm.startBroadcast(deployerPrivateKey);
        exe();
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
    }

    function generateSignature(
        DelegateAble delegateableGt,
        uint256 delegatorPrivateKey,
        DelegateAble.DelegateParameters memory params
    ) public view returns (DelegateAble.Signature memory signature) {
        // Create signature
        bytes32 domainSeparator = delegateableGt.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DelegationWithSig(address delegator,address delegatee,bool isDelegate,uint256 nonce,uint256 deadline)"
                ),
                params.delegator,
                params.delegatee,
                params.isDelegate,
                params.nonce,
                params.deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatorPrivateKey, digest);
        signature = DelegateAble.Signature({v: v, r: r, s: s});
    }
}
