// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Vm} from "forge-std/Vm.sol";

interface IGearingToken {
    function collateralCapacity() external view returns (uint256);
    function getGtConfig() external view returns (GtConfig memory);
}

struct GtConfig {
    address treasurer;
    address market;
    IERC20 debtToken;
    address collateral;
    address ft;
    uint256 maturity;
    LoanConfig loanConfig;
}

struct LoanConfig {
    address oracle;
    uint128 maxLtv;
    uint128 liquidationLtv;
    bool liquidatable;
}

/**
 * @title CheckGTCollateralUsage
 * @notice Script to extract gtAddr from each market and check the collateral capacity usage
 * @dev Run with: forge script script/CheckGTCollateralUsage.s.sol --rpc-url <RPC_URL>
 */
contract CheckGTCollateralUsage is Script {
    using stdJson for string;

    struct MarketInfo {
        string symbol;
        address gt;
        address collateral;
        uint256 collateralCapacity;
        uint256 collateralBalance;
        uint256 usagePercentage;
        uint8 collateralDecimals;
        string collateralSymbol;
    }

    MarketInfo[] public markets;
    // Only show markets with usage > this percentage
    uint256 constant USAGE_THRESHOLD = 20;

    function setUp() public {
        // Nothing to set up
    }

    function run() public {
        console2.log("=== Checking GT Collateral Usage ===");

        // 1. Load market information from market_list.json
        string memory json = vm.readFile("script/deploy/deploydata/market_list.json");

        // Extract the number of markets
        bytes memory marketCountData = vm.parseJson(json, ".data");
        uint256 marketCount = abi.decode(marketCountData, (uint256[])).length;

        console2.log(string.concat("Total Markets Found: ", vm.toString(marketCount)));

        // 2. Process each market
        for (uint256 i = 0; i < marketCount; i++) {
            string memory marketPath = string.concat(".data[", vm.toString(i), "]");

            // Extract market details
            string memory symbol = vm.parseJsonString(json, string.concat(marketPath, ".symbol"));
            address gtAddr = vm.parseJsonAddress(json, string.concat(marketPath, ".contracts.gtAddr"));
            address collateralAddr = vm.parseJsonAddress(json, string.concat(marketPath, ".contracts.collateralAddr"));

            // Skip if GT address is zero (should not happen, but just in case)
            if (gtAddr == address(0)) {
                console2.log(string.concat("Market ", symbol, " has zero GT address, skipping..."));
                continue;
            }

            // Get collateral capacity from GT contract
            IGearingToken gt = IGearingToken(gtAddr);
            uint256 collateralCapacity;
            try gt.collateralCapacity() returns (uint256 capacity) {
                collateralCapacity = capacity;
            } catch {
                console2.log(string.concat("Error getting collateral capacity for ", symbol, ", skipping..."));
                continue;
            }

            // Get collateral token details
            IERC20Metadata collateralToken = IERC20Metadata(collateralAddr);
            uint8 collateralDecimals;
            string memory collateralSymbol;

            try collateralToken.decimals() returns (uint8 decimals) {
                collateralDecimals = decimals;
            } catch {
                collateralDecimals = 18; // Default to 18 if call fails
            }

            try collateralToken.symbol() returns (string memory symbol_) {
                collateralSymbol = symbol_;
            } catch {
                collateralSymbol = "???"; // Default if call fails
            }

            // Get current collateral balance
            uint256 collateralBalance = collateralToken.balanceOf(gtAddr);

            // Calculate usage percentage (with 2 decimal precision - multiply by 10000 and divide by 100)
            uint256 usagePercentage =
                collateralCapacity > 0 ? (collateralBalance * 10000) / collateralCapacity / 100 : 0;

            // Add to markets array
            markets.push(
                MarketInfo({
                    symbol: symbol,
                    gt: gtAddr,
                    collateral: collateralAddr,
                    collateralCapacity: collateralCapacity,
                    collateralBalance: collateralBalance,
                    usagePercentage: usagePercentage,
                    collateralDecimals: collateralDecimals,
                    collateralSymbol: collateralSymbol
                })
            );
        }

        // 3. Count markets with high usage (> USAGE_THRESHOLD%)
        uint256 highUsageCount = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            if (markets[i].usagePercentage > USAGE_THRESHOLD) {
                highUsageCount++;
            }
        }

        // 4. Output results in a table format
        console2.log("\n=== GT Collateral Usage Report (Usage > 20%) ===");

        if (highUsageCount == 0) {
            console2.log("No markets found with collateral usage greater than 20%");
        } else {
            console2.log(string.concat("Found ", vm.toString(highUsageCount), " markets with usage > 20%"));
            console2.log("Market | Collateral | Capacity | Balance | Usage (%)");
            console2.log("-------|------------|----------|---------|----------");

            for (uint256 i = 0; i < markets.length; i++) {
                MarketInfo memory market = markets[i];

                // Skip markets with low usage
                if (market.usagePercentage <= USAGE_THRESHOLD) {
                    continue;
                }

                // Format capacity and balance with proper decimals for readability
                string memory formattedCapacity = _formatAmount(market.collateralCapacity, market.collateralDecimals);
                string memory formattedBalance = _formatAmount(market.collateralBalance, market.collateralDecimals);

                string memory logLine = string.concat(
                    market.symbol,
                    " | ",
                    market.collateralSymbol,
                    " | ",
                    formattedCapacity,
                    " | ",
                    formattedBalance,
                    " | ",
                    vm.toString(market.usagePercentage),
                    "%"
                );

                console2.log(logLine);
            }
        }
    }

    // Helper function to format token amounts with proper decimals
    function _formatAmount(uint256 amount, uint8 decimals) internal view returns (string memory) {
        if (amount == 0) return "0";

        // Convert to string
        string memory amountStr = vm.toString(amount);
        bytes memory amountBytes = bytes(amountStr);

        // Simple approach to avoid array out-of-bounds errors
        if (decimals == 0) {
            // No decimal point needed
            return amountStr;
        } else if (amountBytes.length <= decimals) {
            // Number is less than 1 (e.g., 0.0123)
            // Start with "0."
            string memory result = "0.";

            // Add leading zeros
            for (uint256 i = 0; i < decimals - amountBytes.length; i++) {
                result = string.concat(result, "0");
            }

            // Add the significant digits
            result = string.concat(result, amountStr);
            return result;
        } else {
            // Number is >= 1 (e.g., 123.456)
            uint256 intPartLength = amountBytes.length - decimals;

            // Extract integer part
            bytes memory intPart = new bytes(intPartLength);
            for (uint256 i = 0; i < intPartLength; i++) {
                intPart[i] = amountBytes[i];
            }

            // Extract decimal part
            bytes memory decPart = new bytes(decimals);
            for (uint256 i = 0; i < decimals; i++) {
                if (intPartLength + i < amountBytes.length) {
                    decPart[i] = amountBytes[intPartLength + i];
                } else {
                    decPart[i] = "0";
                }
            }

            // Combine with decimal point
            return string.concat(string(intPart), ".", string(decPart));
        }
    }
}
