// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Interface for the Access Manager
interface IAccessManager {
    function updateGtConfig(address market, bytes memory configData) external;
    function CONFIGURATOR_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
}

// Interface for TermMax Market
interface ITermMaxMarket {
    function tokens() external view returns (IERC20, IERC20, address, address, IERC20);
}

// Interface for Gearing Token
interface IGearingToken {
    function collateralCapacity() external view returns (uint256);
}

/**
 * @title UpdateSingleGTCapacity
 * @notice Forge script to update a single GT collateral capacity through the access manager using global variables
 * @dev All configuration values (addresses, new capacity) are set as global variables in the script
 */
contract UpdateSingleGTCapacity is Script {
    // CONFIGURATION - Update these values before running the script
    // ===============================================================

    // The address of the AccessManager contract
    address public constant ACCESS_MANAGER_ADDRESS = 0xDA4aAF85Bb924B53DCc2DFFa9e1A9C2Ef97aCFDF; // Mainnet

    // The address of the Market contract to update
    address public constant MARKET_ADDRESS = 0x9D7386F68d9001a809860B4D88EC8E2cc3DD81B0; // Example - Replace with actual market address

    // The new collateral capacity value (in wei) to set for the GT
    uint256 public constant NEW_GT_CAPACITY = 5000000e18; // Example: 1,000,000 tokens with 18 decimals

    // Private key environment variable name
    string public constant PRIVATE_KEY_ENV_VAR = "ETH_MAINNET_DEPLOYER_PRIVATE_KEY";
    // ===============================================================

    function setUp() public {
        // Nothing to set up
    }

    function run() public {
        // Validate configuration
        require(ACCESS_MANAGER_ADDRESS != address(0), "Access Manager address not set");
        require(MARKET_ADDRESS != address(0), "Market address not set");
        require(NEW_GT_CAPACITY > 0, "New capacity must be greater than 0");

        // Load private key for transaction signing
        uint256 deployerPrivateKey = vm.envUint(PRIVATE_KEY_ENV_VAR);
        address deployer = vm.addr(deployerPrivateKey);

        // Print script configuration
        printConfiguration(deployer);

        // Check if deployer has configurator role
        IAccessManager accessManager = IAccessManager(ACCESS_MANAGER_ADDRESS);
        bytes32 configuratorRole = accessManager.CONFIGURATOR_ROLE();
        bool hasRole = accessManager.hasRole(configuratorRole, deployer);

        if (!hasRole) {
            console2.log("ERROR: Deployer does not have CONFIGURATOR_ROLE. Cannot update GT config.");
            return;
        }

        // Get GT contract address from market
        ITermMaxMarket market = ITermMaxMarket(MARKET_ADDRESS);
        address gtAddress;
        try market.tokens() returns (IERC20 ft, IERC20 xt, address gt, address collateralAddr, IERC20 underlying) {
            gtAddress = gt;
            console2.log(string.concat("GT Name: ", IERC20Metadata(gtAddress).name()));
            console2.log(string.concat("GT Address: ", vm.toString(gtAddress)));
            console2.log(string.concat("Collateral Address: ", vm.toString(collateralAddr)));
            console2.log(string.concat("Underlying Address: ", vm.toString(address(underlying))));
        } catch {
            console2.log("ERROR: Failed to get token addresses from market.");
            return;
        }

        // Get current collateral capacity for comparison
        IGearingToken gt = IGearingToken(gtAddress);
        uint256 currentCapacity;
        try gt.collateralCapacity() returns (uint256 capacity) {
            currentCapacity = capacity;
            console2.log(string.concat("Current GT capacity: ", vm.toString(currentCapacity)));
        } catch {
            console2.log("WARNING: Could not retrieve current capacity (continuing anyway)");
        }

        // Encode new capacity as config data
        bytes memory configData = abi.encode(NEW_GT_CAPACITY);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Update GT config through access manager
        try accessManager.updateGtConfig(MARKET_ADDRESS, configData) {
            console2.log("Successfully sent updateGtConfig transaction.");
        } catch Error(string memory reason) {
            console2.log(string.concat("Failed to update GT config: ", reason));
            vm.stopBroadcast();
            return;
        } catch {
            console2.log("Failed to update GT config: Unknown error");
            vm.stopBroadcast();
            return;
        }

        vm.stopBroadcast();

        // Verify the update (this will only work with local simulations or --slow flag)
        try gt.collateralCapacity() returns (uint256 updatedCapacity) {
            console2.log(string.concat("Updated GT capacity: ", vm.toString(updatedCapacity)));
            if (updatedCapacity == NEW_GT_CAPACITY) {
                console2.log("[SUCCESS] GT collateral capacity successfully updated!");
            } else {
                console2.log(
                    "[WARNING] Note: Updated capacity doesn't match specified capacity. This may be normal if verifying against a fork."
                );
            }
        } catch {
            console2.log(
                "Note: Could not verify the updated capacity. This is normal when broadcasting to live networks."
            );
        }
    }

    function printConfiguration(address deployer) internal view {
        console2.log("=== Update Single GT Capacity Configuration ===");
        console2.log(string.concat("Access Manager: ", vm.toString(ACCESS_MANAGER_ADDRESS)));
        console2.log(string.concat("Market Address: ", vm.toString(MARKET_ADDRESS)));
        console2.log(string.concat("New GT Capacity: ", vm.toString(NEW_GT_CAPACITY)));
        console2.log(string.concat("Deployer: ", vm.toString(deployer)));
        console2.log("==============================================");
    }
}
