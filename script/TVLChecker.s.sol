// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title TVLChecker
 * @dev Script to check locked amount of underlying and collateral tokens for each market
 */

// Interface for OracleAggregator
interface IOracleAggregator {
    struct Oracle {
        AggregatorV3Interface aggregator;
        AggregatorV3Interface backupAggregator;
        uint32 heartbeat;
    }

    function getPrice(address asset) external view returns (uint256 price, uint8 decimals);
    function oracles(address asset)
        external
        view
        returns (AggregatorV3Interface aggregator, AggregatorV3Interface backupAggregator, uint32 heartbeat);
}

contract TVLChecker is Script {
    struct MarketTVL {
        string marketName;
        address market;
        address gt;
        address ft;
        address xt;
        address underlying;
        address collateral;
        string underlyingSymbol;
        string collateralSymbol;
        uint8 underlyingDecimals;
        uint8 collateralDecimals;
        uint256 underlyingLocked; // Underlying token locked in market
        uint256 collateralLocked; // Collateral token locked in GT
        uint256 underlyingPriceUSD; // USD price of underlying token (scaled by price decimals)
        uint256 collateralPriceUSD; // USD price of collateral token (scaled by price decimals)
        uint8 underlyingPriceDecimals; // Decimals of the underlying price feed
        uint8 collateralPriceDecimals; // Decimals of the collateral price feed
    }

    struct VaultTVL {
        string vaultName;
        address vaultAddress;
        address assetAddress;
        string assetSymbol;
        uint8 assetDecimals;
        uint256 totalAssets;
        uint256 assetPriceUSD;
        uint8 assetPriceDecimals;
    }

    struct TokenSummary {
        address tokenAddress;
        string tokenSymbol;
        uint8 tokenDecimals;
        uint256 totalLocked;
        uint256 tokenPriceUSD;
        uint8 tokenPriceDecimals;
    }

    function run() public {
        // Directory to look for deployment files
        string memory deploymentDir = "deployments/eth-mainnet-v1.0.8-20250530";

        // Read oracle aggregator address from core.json
        string memory coreJsonPath = string.concat(deploymentDir, "/eth-mainnet-core.json");
        string memory coreJson = vm.readFile(coreJsonPath);
        address oracleAggregator = vm.parseJsonAddress(coreJson, ".contracts.oracleAggregator");

        console2.log("Oracle Aggregator:", formatAddress(oracleAggregator));

        // First, count the market files to determine array size
        uint256 marketCount = countMarketFiles(deploymentDir);
        MarketTVL[] memory markets = new MarketTVL[](marketCount);

        // Count vault files
        uint256 vaultCount = countVaultFiles(deploymentDir);
        VaultTVL[] memory vaults = new VaultTVL[](vaultCount);

        console2.log("====== Checking TVL for ETH Mainnet Markets and Vaults ======");
        console2.log(string.concat("Directory: ", deploymentDir));
        console2.log(
            string.concat(
                "Found ", vm.toString(marketCount), " market files and ", vm.toString(vaultCount), " vault files"
            )
        );
        console2.log("=================================================");

        // Process market files
        processMarketFiles(deploymentDir, markets, oracleAggregator);

        // Process vault files
        processVaultFiles(deploymentDir, vaults, oracleAggregator);

        // Display results for markets
        console2.log("\n====== MARKET TVL SUMMARY ======");

        uint256 totalUnderlyingValueUSD = 0;
        uint256 totalCollateralValueUSD = 0;

        for (uint256 i = 0; i < marketCount; i++) {
            MarketTVL memory info = markets[i];

            // Format balances with proper decimals
            string memory formattedUnderlyingLocked = formatTokenAmount(info.underlyingLocked, info.underlyingDecimals);
            string memory formattedCollateralLocked = formatTokenAmount(info.collateralLocked, info.collateralDecimals);

            // Calculate USD values with proper decimal adjustment
            uint256 underlyingValueUSD = calculateUSDValue(
                info.underlyingLocked, info.underlyingDecimals, info.underlyingPriceUSD, info.underlyingPriceDecimals
            );

            uint256 collateralValueUSD = calculateUSDValue(
                info.collateralLocked, info.collateralDecimals, info.collateralPriceUSD, info.collateralPriceDecimals
            );

            // Add to totals (normalize to 18 decimals for addition)
            totalUnderlyingValueUSD += underlyingValueUSD;
            totalCollateralValueUSD += collateralValueUSD;

            // Format USD values as dollars with 2 decimal places
            string memory formattedUnderlyingValueUSD = formatUSDValue(underlyingValueUSD);
            string memory formattedCollateralValueUSD = formatUSDValue(collateralValueUSD);

            // Display results in the requested format
            console2.log("-------------------------------------------------");
            console2.log(string.concat("Market: ", info.marketName));
            console2.log(string.concat("Market address: ", formatAddress(info.market)));
            console2.log(string.concat("GT address: ", formatAddress(info.gt)));
            console2.log(string.concat("FT address: ", formatAddress(info.ft)));
            console2.log(string.concat("XT address: ", formatAddress(info.xt)));
            console2.log(string.concat("Underlying address: ", formatAddress(info.underlying)));
            console2.log(string.concat("Collateral address: ", formatAddress(info.collateral)));
            console2.log(string.concat("Underlying locked: ", formattedUnderlyingLocked, " ", info.underlyingSymbol));
            console2.log(string.concat("Underlying USD value: $", formattedUnderlyingValueUSD));
            console2.log(string.concat("Collateral locked: ", formattedCollateralLocked, " ", info.collateralSymbol));
            console2.log(string.concat("Collateral USD value: $", formattedCollateralValueUSD));
        }

        // Display results for vaults
        console2.log("\n====== VAULT TVL SUMMARY ======");

        uint256 totalVaultValueUSD = 0;

        for (uint256 i = 0; i < vaultCount; i++) {
            VaultTVL memory info = vaults[i];

            // Format asset amount with proper decimals
            string memory formattedAssets = formatTokenAmount(info.totalAssets, info.assetDecimals);

            // Calculate USD value
            uint256 assetValueUSD =
                calculateUSDValue(info.totalAssets, info.assetDecimals, info.assetPriceUSD, info.assetPriceDecimals);

            // Add to total
            totalVaultValueUSD += assetValueUSD;

            // Format USD value
            string memory formattedAssetValueUSD = formatUSDValue(assetValueUSD);

            // Display results
            console2.log("-------------------------------------------------");
            console2.log(string.concat("Vault: ", info.vaultName));
            console2.log(string.concat("Vault address: ", formatAddress(info.vaultAddress)));
            console2.log(string.concat("Asset address: ", formatAddress(info.assetAddress)));
            console2.log(string.concat("Asset locked: ", formattedAssets, " ", info.assetSymbol));
            console2.log(string.concat("Asset USD value: $", formattedAssetValueUSD));
        }

        // Create and display token summary
        console2.log("\n====== TOKEN-BASED TVL SUMMARY ======");

        // 1. Collect all unique token addresses
        address[] memory uniqueTokens = collectUniqueTokens(markets, vaults);
        TokenSummary[] memory tokenSummaries = new TokenSummary[](uniqueTokens.length);

        // 2. Initialize token summaries
        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            TokenSummary memory summary;
            summary.tokenAddress = uniqueTokens[i];

            try IERC20Metadata(uniqueTokens[i]).symbol() returns (string memory symbol) {
                summary.tokenSymbol = symbol;
            } catch {
                summary.tokenSymbol = "Unknown";
            }

            try IERC20Metadata(uniqueTokens[i]).decimals() returns (uint8 decimals) {
                summary.tokenDecimals = decimals;
            } catch {
                summary.tokenDecimals = 18;
            }

            // Try to get price from oracle
            IOracleAggregator oracle = IOracleAggregator(oracleAggregator);
            try oracle.getPrice(uniqueTokens[i]) returns (uint256 price, uint8 decimals) {
                summary.tokenPriceUSD = price;
                summary.tokenPriceDecimals = decimals;
            } catch {
                summary.tokenPriceUSD = 0;
                summary.tokenPriceDecimals = 8;
            }

            tokenSummaries[i] = summary;
        }

        // 3. Accumulate locked amounts for each token
        for (uint256 i = 0; i < marketCount; i++) {
            // Add underlying tokens from markets
            for (uint256 j = 0; j < uniqueTokens.length; j++) {
                if (markets[i].underlying == uniqueTokens[j]) {
                    tokenSummaries[j].totalLocked += markets[i].underlyingLocked;
                    break;
                }
            }

            // Add collateral tokens from markets
            for (uint256 j = 0; j < uniqueTokens.length; j++) {
                if (markets[i].collateral == uniqueTokens[j]) {
                    tokenSummaries[j].totalLocked += markets[i].collateralLocked;
                    break;
                }
            }
        }

        // Add assets from vaults
        for (uint256 i = 0; i < vaultCount; i++) {
            for (uint256 j = 0; j < uniqueTokens.length; j++) {
                if (vaults[i].assetAddress == uniqueTokens[j]) {
                    tokenSummaries[j].totalLocked += vaults[i].totalAssets;
                    break;
                }
            }
        }

        // 4. Display token summaries
        uint256 totalTokenValueUSD = 0;

        for (uint256 i = 0; i < tokenSummaries.length; i++) {
            TokenSummary memory summary = tokenSummaries[i];

            // Skip tokens with zero balance
            if (summary.totalLocked == 0) continue;

            // Format amount with proper decimals
            string memory formattedAmount = formatTokenAmount(summary.totalLocked, summary.tokenDecimals);

            // Calculate USD value
            uint256 tokenValueUSD = calculateUSDValue(
                summary.totalLocked, summary.tokenDecimals, summary.tokenPriceUSD, summary.tokenPriceDecimals
            );

            totalTokenValueUSD += tokenValueUSD;
            string memory formattedTokenValueUSD = formatUSDValue(tokenValueUSD);

            // Display the token summary
            console2.log("-------------------------------------------------");
            console2.log(string.concat("Token: ", summary.tokenSymbol));
            console2.log(string.concat("Address: ", formatAddress(summary.tokenAddress)));
            console2.log(string.concat("Total locked: ", formattedAmount, " ", summary.tokenSymbol));
            console2.log(string.concat("USD value: $", formattedTokenValueUSD));
        }

        // Display grand totals
        string memory formattedTotalUnderlyingUSD = formatUSDValue(totalUnderlyingValueUSD);
        string memory formattedTotalCollateralUSD = formatUSDValue(totalCollateralValueUSD);
        string memory formattedTotalVaultUSD = formatUSDValue(totalVaultValueUSD);
        string memory formattedGrandTotalTVL =
            formatUSDValue(totalUnderlyingValueUSD + totalCollateralValueUSD + totalVaultValueUSD);

        console2.log("\n====== TOTAL TVL SUMMARY ======");
        console2.log("-------------------------------------------------");
        console2.log(string.concat("Total Market Underlying USD Value: $", formattedTotalUnderlyingUSD));
        console2.log(string.concat("Total Market Collateral USD Value: $", formattedTotalCollateralUSD));
        console2.log(string.concat("Total Vault USD Value: $", formattedTotalVaultUSD));
        console2.log(string.concat("GRAND TOTAL TVL: $", formattedGrandTotalTVL));
        console2.log("-------------------------------------------------");
    }

    // Collect unique token addresses from markets and vaults
    function collectUniqueTokens(MarketTVL[] memory markets, VaultTVL[] memory vaults)
        internal
        pure
        returns (address[] memory)
    {
        // First, count the maximum possible unique tokens (2 per market + 1 per vault)
        uint256 maxUniqueTokens = markets.length * 2 + vaults.length;
        address[] memory tempTokens = new address[](maxUniqueTokens);
        uint256 uniqueCount = 0;

        // Add market tokens (underlying and collateral)
        for (uint256 i = 0; i < markets.length; i++) {
            // Add underlying token if not already in the list
            bool foundUnderlying = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempTokens[j] == markets[i].underlying) {
                    foundUnderlying = true;
                    break;
                }
            }
            if (!foundUnderlying && markets[i].underlying != address(0)) {
                tempTokens[uniqueCount] = markets[i].underlying;
                uniqueCount++;
            }

            // Add collateral token if not already in the list
            bool foundCollateral = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempTokens[j] == markets[i].collateral) {
                    foundCollateral = true;
                    break;
                }
            }
            if (!foundCollateral && markets[i].collateral != address(0)) {
                tempTokens[uniqueCount] = markets[i].collateral;
                uniqueCount++;
            }
        }

        // Add vault asset tokens
        for (uint256 i = 0; i < vaults.length; i++) {
            bool foundAsset = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempTokens[j] == vaults[i].assetAddress) {
                    foundAsset = true;
                    break;
                }
            }
            if (!foundAsset && vaults[i].assetAddress != address(0)) {
                tempTokens[uniqueCount] = vaults[i].assetAddress;
                uniqueCount++;
            }
        }

        // Create correctly sized array with unique tokens
        address[] memory uniqueTokens = new address[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            uniqueTokens[i] = tempTokens[i];
        }

        return uniqueTokens;
    }

    // Calculate USD value from token amount and price
    function calculateUSDValue(uint256 tokenAmount, uint8 tokenDecimals, uint256 tokenPrice, uint8 priceDecimals)
        internal
        pure
        returns (uint256)
    {
        if (tokenAmount == 0 || tokenPrice == 0) return 0;

        // Convert to 18 decimal standard for consistency
        uint256 normalizedAmount;
        if (tokenDecimals < 18) {
            normalizedAmount = tokenAmount * 10 ** (18 - tokenDecimals);
        } else if (tokenDecimals > 18) {
            normalizedAmount = tokenAmount / 10 ** (tokenDecimals - 18);
        } else {
            normalizedAmount = tokenAmount;
        }

        // Scale price to 18 decimals
        uint256 normalizedPrice;
        if (priceDecimals < 18) {
            normalizedPrice = tokenPrice * 10 ** (18 - priceDecimals);
        } else if (priceDecimals > 18) {
            normalizedPrice = tokenPrice / 10 ** (priceDecimals - 18);
        } else {
            normalizedPrice = tokenPrice;
        }

        // Calculate value and return with 18 decimals precision
        return (normalizedAmount * normalizedPrice) / 10 ** 18;
    }

    // Format USD value as string with 2 decimal places
    function formatUSDValue(uint256 valueUSD) internal pure returns (string memory) {
        // Convert to dollars with 2 decimal places (USD value is in 18 decimals)
        uint256 dollars = valueUSD / 10 ** 16; // Get dollars with 2 decimal places
        string memory integerPart = vm.toString(dollars / 100);
        uint256 fractionalPart = dollars % 100;

        // Ensure fractional part has leading zeros
        string memory fractionalStr;
        if (fractionalPart < 10) {
            fractionalStr = string.concat("0", vm.toString(fractionalPart));
        } else {
            fractionalStr = vm.toString(fractionalPart);
        }

        return string.concat(integerPart, ".", fractionalStr);
    }

    // Count how many market files are in the directory
    function countMarketFiles(string memory deploymentDir) internal returns (uint256) {
        string[] memory inputs = new string[](3);
        inputs[0] = "ls";
        inputs[1] = "-1"; // One file per line
        inputs[2] = deploymentDir;

        bytes memory result = vm.ffi(inputs);
        string memory fileList = string(result);

        string[] memory files = split(fileList, "\n");
        uint256 marketCount = 0;

        for (uint256 i = 0; i < files.length; i++) {
            if (contains(files[i], "market-") && contains(files[i], ".json")) {
                marketCount++;
            }
        }
        return marketCount;
    }

    // Count how many vault files are in the directory
    function countVaultFiles(string memory deploymentDir) internal returns (uint256) {
        string[] memory inputs = new string[](3);
        inputs[0] = "ls";
        inputs[1] = "-1"; // One file per line
        inputs[2] = deploymentDir;

        bytes memory result = vm.ffi(inputs);
        string memory fileList = string(result);

        string[] memory files = split(fileList, "\n");
        uint256 vaultCount = 0;

        for (uint256 i = 0; i < files.length; i++) {
            if (contains(files[i], "vault-") && contains(files[i], ".json") && !contains(files[i], "factory")) {
                vaultCount++;
            }
        }
        return vaultCount;
    }

    // Process market files and extract TVL information
    function processMarketFiles(string memory deploymentDir, MarketTVL[] memory markets, address oracleAggregator)
        internal
    {
        string[] memory inputs = new string[](3);
        inputs[0] = "ls";
        inputs[1] = "-1"; // One file per line
        inputs[2] = deploymentDir;

        bytes memory result = vm.ffi(inputs);
        string memory fileList = string(result);

        string[] memory files = split(fileList, "\n");
        uint256 marketIndex = 0;

        for (uint256 i = 0; i < files.length; i++) {
            if (contains(files[i], "market-") && contains(files[i], ".json")) {
                string memory filePath = string.concat(deploymentDir, "/", files[i]);
                string memory jsonContent = vm.readFile(filePath);

                // Extract market name from file path
                markets[marketIndex].marketName = extractMarketName(files[i]);

                // Extract addresses from JSON
                markets[marketIndex].market = vm.parseJsonAddress(jsonContent, ".market");
                markets[marketIndex].underlying = vm.parseJsonAddress(jsonContent, ".underlying.address");
                markets[marketIndex].collateral = vm.parseJsonAddress(jsonContent, ".collateral.address");
                markets[marketIndex].ft = vm.parseJsonAddress(jsonContent, ".tokens.ft");
                markets[marketIndex].xt = vm.parseJsonAddress(jsonContent, ".tokens.xt");
                markets[marketIndex].gt = vm.parseJsonAddress(jsonContent, ".tokens.gt");

                // Get token symbols and decimals
                try IERC20Metadata(markets[marketIndex].underlying).symbol() returns (string memory symbol) {
                    markets[marketIndex].underlyingSymbol = symbol;
                } catch {
                    markets[marketIndex].underlyingSymbol = "Unknown";
                }

                try IERC20Metadata(markets[marketIndex].collateral).symbol() returns (string memory symbol) {
                    markets[marketIndex].collateralSymbol = symbol;
                } catch {
                    markets[marketIndex].collateralSymbol = "Unknown";
                }

                try IERC20Metadata(markets[marketIndex].underlying).decimals() returns (uint8 decimals) {
                    markets[marketIndex].underlyingDecimals = decimals;
                } catch {
                    markets[marketIndex].underlyingDecimals = 18;
                }

                try IERC20Metadata(markets[marketIndex].collateral).decimals() returns (uint8 decimals) {
                    markets[marketIndex].collateralDecimals = decimals;
                } catch {
                    markets[marketIndex].collateralDecimals = 18;
                }

                // Check locked balances
                try IERC20(markets[marketIndex].underlying).balanceOf(markets[marketIndex].market) returns (
                    uint256 balance
                ) {
                    markets[marketIndex].underlyingLocked = balance;
                } catch {
                    console2.log(
                        string.concat(
                            "Error: Could not fetch underlying balance for market ",
                            formatAddress(markets[marketIndex].market)
                        )
                    );
                }

                try IERC20(markets[marketIndex].collateral).balanceOf(markets[marketIndex].gt) returns (uint256 balance)
                {
                    markets[marketIndex].collateralLocked = balance;
                } catch {
                    console2.log(
                        string.concat(
                            "Error: Could not fetch collateral balance for GT ", formatAddress(markets[marketIndex].gt)
                        )
                    );
                }

                // Get token prices from oracle aggregator
                IOracleAggregator oracle = IOracleAggregator(oracleAggregator);

                try oracle.getPrice(markets[marketIndex].underlying) returns (uint256 price, uint8 decimals) {
                    markets[marketIndex].underlyingPriceUSD = price;
                    markets[marketIndex].underlyingPriceDecimals = decimals;
                } catch {
                    console2.log(
                        string.concat(
                            "Error: Could not fetch underlying price for ", markets[marketIndex].underlyingSymbol
                        )
                    );
                    // Set defaults
                    markets[marketIndex].underlyingPriceUSD = 0;
                    markets[marketIndex].underlyingPriceDecimals = 8; // Default Chainlink decimals
                }

                try oracle.getPrice(markets[marketIndex].collateral) returns (uint256 price, uint8 decimals) {
                    markets[marketIndex].collateralPriceUSD = price;
                    markets[marketIndex].collateralPriceDecimals = decimals;
                } catch {
                    console2.log(
                        string.concat(
                            "Error: Could not fetch collateral price for ", markets[marketIndex].collateralSymbol
                        )
                    );
                    // Set defaults
                    markets[marketIndex].collateralPriceUSD = 0;
                    markets[marketIndex].collateralPriceDecimals = 8; // Default Chainlink decimals
                }

                marketIndex++;
            }
        }
    }

    // Process vault files and extract TVL information
    function processVaultFiles(string memory deploymentDir, VaultTVL[] memory vaults, address oracleAggregator)
        internal
    {
        string[] memory inputs = new string[](3);
        inputs[0] = "ls";
        inputs[1] = "-1"; // One file per line
        inputs[2] = deploymentDir;

        bytes memory result = vm.ffi(inputs);
        string memory fileList = string(result);

        string[] memory files = split(fileList, "\n");
        uint256 vaultIndex = 0;

        for (uint256 i = 0; i < files.length; i++) {
            if (contains(files[i], "vault-") && contains(files[i], ".json") && !contains(files[i], "factory")) {
                string memory filePath = string.concat(deploymentDir, "/", files[i]);
                string memory jsonContent = vm.readFile(filePath);

                // Extract vault name from file path
                vaults[vaultIndex].vaultName = extractVaultName(files[i]);

                // Extract addresses from JSON
                vaults[vaultIndex].vaultAddress = vm.parseJsonAddress(jsonContent, ".vaultInfo.address");
                vaults[vaultIndex].assetAddress = vm.parseJsonAddress(jsonContent, ".vaultInfo.asset");

                // Get token symbol and decimals
                try IERC20Metadata(vaults[vaultIndex].assetAddress).symbol() returns (string memory symbol) {
                    vaults[vaultIndex].assetSymbol = symbol;
                } catch {
                    vaults[vaultIndex].assetSymbol = "Unknown";
                }

                try IERC20Metadata(vaults[vaultIndex].assetAddress).decimals() returns (uint8 decimals) {
                    vaults[vaultIndex].assetDecimals = decimals;
                } catch {
                    vaults[vaultIndex].assetDecimals = 18;
                }

                // Get asset balance of the vault using balanceOf instead of totalAssets
                // try IERC4626(vaults[vaultIndex].vaultAddress).totalAssets() returns (uint256 balance) {
                try IERC20(vaults[vaultIndex].assetAddress).balanceOf(vaults[vaultIndex].vaultAddress) returns (
                    uint256 balance
                ) {
                    vaults[vaultIndex].totalAssets = balance;
                } catch {
                    console2.log(
                        string.concat(
                            "Error: Could not fetch asset balance for vault ",
                            formatAddress(vaults[vaultIndex].vaultAddress)
                        )
                    );
                }

                // Get asset price from oracle aggregator
                IOracleAggregator oracle = IOracleAggregator(oracleAggregator);

                try oracle.getPrice(vaults[vaultIndex].assetAddress) returns (uint256 price, uint8 decimals) {
                    vaults[vaultIndex].assetPriceUSD = price;
                    vaults[vaultIndex].assetPriceDecimals = decimals;
                } catch {
                    console2.log(string.concat("Error: Could not fetch price for ", vaults[vaultIndex].assetSymbol));
                    // Set defaults
                    vaults[vaultIndex].assetPriceUSD = 0;
                    vaults[vaultIndex].assetPriceDecimals = 8; // Default Chainlink decimals
                }

                vaultIndex++;
            }
        }
    }

    // Check if a string contains a substring
    function contains(string memory source, string memory target) internal pure returns (bool) {
        bytes memory sourceBytes = bytes(source);
        bytes memory targetBytes = bytes(target);

        if (targetBytes.length > sourceBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= sourceBytes.length - targetBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < targetBytes.length; j++) {
                if (sourceBytes[i + j] != targetBytes[j]) {
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

    // Split a string by delimiter
    function split(string memory source, string memory delimiter) internal pure returns (string[] memory) {
        bytes memory sourceBytes = bytes(source);
        bytes memory delimiterBytes = bytes(delimiter);

        // Count occurrences of delimiter
        uint256 count = 1; // At least one item
        for (uint256 i = 0; i < sourceBytes.length - delimiterBytes.length + 1; i++) {
            bool found = true;
            for (uint256 j = 0; j < delimiterBytes.length; j++) {
                if (sourceBytes[i + j] != delimiterBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                count++;
                i += delimiterBytes.length - 1;
            }
        }

        // Split the string
        string[] memory parts = new string[](count);
        uint256 partIndex = 0;
        uint256 startIndex = 0;

        for (uint256 i = 0; i <= sourceBytes.length - delimiterBytes.length + 1; i++) {
            if (i == sourceBytes.length - delimiterBytes.length + 1) {
                // Add the last part
                parts[partIndex] = substring(source, startIndex, sourceBytes.length);
                break;
            }

            bool found = true;
            for (uint256 j = 0; j < delimiterBytes.length; j++) {
                if (i + j >= sourceBytes.length || sourceBytes[i + j] != delimiterBytes[j]) {
                    found = false;
                    break;
                }
            }

            if (found) {
                parts[partIndex] = substring(source, startIndex, i);
                partIndex++;
                startIndex = i + delimiterBytes.length;
                i += delimiterBytes.length - 1;
            }
        }

        return parts;
    }

    // Helper function to format token amounts with proper decimals
    function formatTokenAmount(uint256 amount, uint8 decimals) internal pure returns (string memory) {
        if (amount == 0) return "0";

        string memory amountStr = vm.toString(amount);
        uint256 length = bytes(amountStr).length;

        // Format with proper decimals, showing all digits
        if (length <= decimals) {
            // Need to pad with leading zeros
            string memory zeros = "";
            for (uint256 i = 0; i < decimals - length; i++) {
                zeros = string.concat(zeros, "0");
            }
            return string.concat("0.", zeros, amountStr);
        } else {
            // Insert decimal point
            uint256 decimalPos = length - decimals;
            return string.concat(substring(amountStr, 0, decimalPos), ".", substring(amountStr, decimalPos, length));
        }
    }

    // Helper function to format address for display
    function formatAddress(address addr) internal pure returns (string memory) {
        return vm.toString(addr);
    }

    // Helper function to get a substring
    function substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    // Extract market name from file path
    function extractMarketName(string memory fileName) internal pure returns (string memory) {
        // Example fileName: eth-mainnet-market-USDC-WBTC@30MAY2025.json
        // We want to extract: USDC-WBTC@30MAY2025

        string[] memory parts = split(fileName, "market-");
        if (parts.length < 2) return fileName;

        string memory marketPart = parts[1];
        string[] memory jsonParts = split(marketPart, ".json");

        return jsonParts[0];
    }

    // Extract vault name from file path
    function extractVaultName(string memory fileName) internal pure returns (string memory) {
        // Example fileName: eth-mainnet-vault-TMX-WETH.json
        // We want to extract: TMX-WETH

        string[] memory parts = split(fileName, "vault-");
        if (parts.length < 2) return fileName;

        string memory vaultPart = parts[1];
        string[] memory jsonParts = split(vaultPart, ".json");

        return jsonParts[0];
    }
}
