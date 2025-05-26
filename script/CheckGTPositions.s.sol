// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Vm} from "forge-std/Vm.sol";
import {IGearingToken} from "../contracts/tokens/IGearingToken.sol";

interface IGT is IERC721Enumerable {
    function tokenURI(uint256 tokenId) external view returns (string memory);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function getLockupInfo(uint256 tokenId) external view returns (address, uint256, uint256);
    function getActiveAmount(uint256 tokenId) external view returns (uint256);
    function getBalanceLocked(uint256 tokenId) external view returns (uint256);
}

/**
 * @title CheckGTPositions
 * @notice Script to extract all addresses from market config files and list active GT positions
 * @dev Run with: forge script script/CheckGTPositions.s.sol --rpc-url <RPC_URL>
 */
contract CheckGTPositions is Script, ERC721Holder {
    struct MarketInfo {
        string name;
        address market;
        address ft;
        address xt;
        address gt;
        address underlying;
        string underlyingSymbol;
        address collateral;
        string collateralSymbol;
    }

    struct GTPosition {
        uint256 tokenId;
        uint256 activeAmount;
        uint256 lockedAmount;
        address owner;
        uint256 lockupStart;
        uint256 lockupEnd;
    }

    MarketInfo[] public markets;
    string constant DEPLOYMENT_DIR = "eth-mainnet-v1.0.8-20250404-2000";

    function setUp() public {
        // Nothing to set up
    }

    function run() public {
        console.log("=== Extracting Market Addresses and GT Positions ===");

        // 1. Load all market configurations
        string memory deploymentPath = string.concat(vm.projectRoot(), "/deployments/", DEPLOYMENT_DIR, "/");

        // Read directory contents
        string[] memory files = getFilesInDirectory(deploymentPath);

        // Filter for market files
        for (uint256 i = 0; i < files.length; i++) {
            string memory file = files[i];

            // Only process market files
            if (contains(file, "market-") && contains(file, ".json")) {
                processMarketFile(string.concat(deploymentPath, file));
            }
        }

        // 2. Print summary of all markets
        console.log("\n=== Market Addresses Summary ===");
        console.log("Total Markets Found: %d", markets.length);

        for (uint256 i = 0; i < markets.length; i++) {
            MarketInfo memory market = markets[i];
            console.log("\nMarket %d: %s", i + 1, market.name);
            console.log("Market Address: %s", market.market);
            console.log("Underlying: %s (%s)", market.underlyingSymbol, market.underlying);
            console.log("Collateral: %s (%s)", market.collateralSymbol, market.collateral);
            console.log("GT Address: %s", market.gt);
            console.log("FT Address: %s", market.ft);
            console.log("XT Address: %s", market.xt);
        }

        // 3. Check active GT positions for each market
        console.log("\n=== Active GT Positions ===");

        for (uint256 i = 0; i < markets.length; i++) {
            MarketInfo memory market = markets[i];
            console.log("\n--- Market: %s ---", market.name);

            IGearingToken gt = IGearingToken(market.gt);
            uint256 totalSupply = gt.totalSupply();

            // Skip if no GTs minted
            if (totalSupply == 0) {
                console.log("No GT tokens minted for this market");
                continue;
            }

            console.log("Total GT Tokens: %d", totalSupply);
            uint256 activePositions = 0;

            for (uint256 tokenId = 1; tokenId <= totalSupply; tokenId++) {
                // This token exists, check if it's active
                activePositions++;

                (address owner, uint128 debtAmt, bytes memory collateralData) = gt.loanInfo(tokenId);
                uint256 collateralAmt = abi.decode(collateralData, (uint256));

                // Print position details
                console.log("GT #%d - Owner: %s", tokenId, owner);
                console.log("  Debt Amount: %d", debtAmt);
                console.log("  Collateral Amount: %d", collateralAmt);
            }

            if (activePositions == 0) {
                console.log("No active GT positions found");
            } else {
                console.log("Total Active GT Positions: %d", activePositions);
            }
        }
    }

    // Helper function to get files in a directory without using vm.readDir directly
    function getFilesInDirectory(string memory path) internal returns (string[] memory) {
        // Get a list of all files in the directory using shell command
        string[] memory inputs = new string[](3);
        inputs[0] = "ls";
        inputs[1] = "-1"; // One file per line
        inputs[2] = path;

        bytes memory res = vm.ffi(inputs);
        string memory result = string(res);

        // Split the result by newlines to get individual files
        return split(result, "\n");
    }

    // Helper function to split a string by delimiter
    function split(string memory _base, string memory _delimiter) internal pure returns (string[] memory) {
        bytes memory baseBytes = bytes(_base);

        // Count the number of delimiters to determine array size
        uint256 count = 1;
        for (uint256 i = 0; i < baseBytes.length; i++) {
            bytes memory delimiter = bytes(_delimiter);
            bool found = true;

            if (i + delimiter.length > baseBytes.length) {
                found = false;
            } else {
                for (uint256 j = 0; j < delimiter.length; j++) {
                    if (baseBytes[i + j] != delimiter[j]) {
                        found = false;
                        break;
                    }
                }
            }

            if (found) {
                count++;
                i += delimiter.length - 1;
            }
        }

        // Create the array and split the string
        string[] memory parts = new string[](count);
        uint256 partIndex = 0;
        uint256 startIndex = 0;

        for (uint256 i = 0; i <= baseBytes.length; i++) {
            if (
                i == baseBytes.length
                    || (i + bytes(_delimiter).length <= baseBytes.length && isMatch(baseBytes, i, bytes(_delimiter)))
            ) {
                // Extract the part
                bytes memory part = new bytes(i - startIndex);
                for (uint256 j = 0; j < part.length; j++) {
                    part[j] = baseBytes[startIndex + j];
                }

                parts[partIndex] = string(part);
                partIndex++;

                if (i < baseBytes.length) {
                    i += bytes(_delimiter).length - 1;
                    startIndex = i + 1;
                }
            }
        }

        return parts;
    }

    // Helper function to check if there's a delimiter match at position
    function isMatch(bytes memory _base, uint256 _position, bytes memory _match) internal pure returns (bool) {
        if (_position + _match.length > _base.length) {
            return false;
        }

        for (uint256 i = 0; i < _match.length; i++) {
            if (_base[_position + i] != _match[i]) {
                return false;
            }
        }

        return true;
    }

    function processMarketFile(string memory filePath) internal {
        string memory json = vm.readFile(filePath);

        // Extract market name from file path
        string memory fileName = extractFileName(filePath);

        // Extract addresses
        address marketAddr = vm.parseJsonAddress(json, ".market");
        address underlying = vm.parseJsonAddress(json, ".underlying.address");
        string memory underlyingSymbol = vm.parseJsonString(json, ".underlying.symbol");
        address collateral = vm.parseJsonAddress(json, ".collateral.address");
        string memory collateralSymbol = vm.parseJsonString(json, ".collateral.symbol");
        address ftAddr = vm.parseJsonAddress(json, ".tokens.ft");
        address xtAddr = vm.parseJsonAddress(json, ".tokens.xt");
        address gtAddr = vm.parseJsonAddress(json, ".tokens.gt");

        // Add to markets array
        markets.push(
            MarketInfo({
                name: fileName,
                market: marketAddr,
                ft: ftAddr,
                xt: xtAddr,
                gt: gtAddr,
                underlying: underlying,
                underlyingSymbol: underlyingSymbol,
                collateral: collateral,
                collateralSymbol: collateralSymbol
            })
        );
    }

    // Helper function to check if a string contains a substring
    function contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > strBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;

            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }

            if (found) {
                return true;
            }
        }

        return false;
    }

    // Helper function to extract file name from path
    function extractFileName(string memory filePath) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(filePath);
        uint256 lastSlash = 0;

        // Find the last slash in the path
        for (uint256 i = 0; i < pathBytes.length; i++) {
            if (pathBytes[i] == bytes1("/")) {
                lastSlash = i;
            }
        }

        // Create the substring from after the last slash
        bytes memory result = new bytes(pathBytes.length - lastSlash - 1);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = pathBytes[lastSlash + 1 + i];
        }

        return string(result);
    }

    // Helper function to format unix timestamp
    function formatTimestamp(uint256 timestamp) internal pure returns (string memory) {
        if (timestamp == 0) {
            return "N/A";
        }

        // Convert timestamp to a human-readable date - simplified version
        return vm.toString(timestamp);
    }
}
