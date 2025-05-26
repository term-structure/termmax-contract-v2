// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ITermMaxMarket} from "contracts/ITermMaxMarket.sol";
import {IGearingToken} from "contracts/tokens/IGearingToken.sol";
import {IMintableERC20} from "contracts/tokens/IMintableERC20.sol";
/**
 * @title CheckMarketStatus
 * @dev Script to check status of markets and GTs
 */

contract CheckMarketStatus is Script {
    struct MarketInfo {
        string fileName;
        address market;
        address underlying;
        address collateral;
        address ft;
        address xt;
        address gt;
        string underlyingSymbol;
        string collateralSymbol;
        uint8 underlyingDecimals;
        uint8 collateralDecimals;
        uint256 underlyingBalance; // Underlying balance in market
        uint256 collateralBalance; // Collateral balance in GT
        uint256 ftTotalSupply; // Total supply of FT
        uint256 treasurerUnderlyingBalance; // Treasurer's underlying balance
        uint256 treasurerFtBalance; // Treasurer's FT balance
        uint256 ftInMarketBalance; // FT balance in the market
    }

    function run() public {
        // Directory to look for deployment files
        string memory deploymentDir = "deployments/eth-mainnet-v1.0.8-20250410-2000";

        // Set treasurer address
        address treasurer = 0x719e77027952929ed3060dbFFC5D43EC50c1cf79;

        // First, count the market files to determine array size
        uint256 marketCount = countMarketFiles(deploymentDir);
        MarketInfo[] memory markets = new MarketInfo[](marketCount);
        uint256 marketIndex = 0;

        console2.log("====== Checking Balances for ETH Mainnet Markets ======");
        console2.log(string.concat("Directory: ", deploymentDir));
        console2.log(string.concat("Found ", vm.toString(marketCount), " market files"));
        console2.log(string.concat("Treasurer: ", formatAddress(treasurer)));
        console2.log("=====================================================");

        // Process market files
        processMarketFiles(deploymentDir, markets, false, treasurer);

        // Display results
        console2.log("\n====== MARKET BALANCES SUMMARY ======");

        for (uint256 i = 0; i < marketCount; i++) {
            MarketInfo memory info = markets[i];

            // Extract market name from file path
            string memory marketName = extractMarketName(info.fileName);

            // Format underlying balance with proper decimals
            string memory formattedUnderlyingBalance =
                formatTokenAmount(info.underlyingBalance, info.underlyingDecimals);

            // Format collateral balance with proper decimals
            string memory formattedCollateralBalance =
                formatTokenAmount(info.collateralBalance, info.collateralDecimals);

            // Format FT total supply
            string memory formattedFtSupply = formatTokenAmount(info.ftTotalSupply, info.underlyingDecimals);

            // Format FT in market balance
            string memory formattedFtInMarket = formatTokenAmount(info.ftInMarketBalance, info.underlyingDecimals);

            // Format treasurer balances
            string memory formattedTreasurerUnderlyingBalance =
                formatTokenAmount(info.treasurerUnderlyingBalance, info.underlyingDecimals);
            string memory formattedTreasurerFtBalance =
                formatTokenAmount(info.treasurerFtBalance, info.underlyingDecimals);

            // Display results in the requested format
            console2.log("---------------------------------------------------------------");
            console2.log(string.concat("Market: ", marketName));
            console2.log(string.concat("Market address: ", formatAddress(info.market)));
            console2.log(
                string.concat("Underlying in market: ", formattedUnderlyingBalance, " ", info.underlyingSymbol)
            );
            console2.log(string.concat("Collateral in GT: ", formattedCollateralBalance, " ", info.collateralSymbol));
            console2.log(string.concat("FT total supply: ", formattedFtSupply, " ", info.underlyingSymbol));
            console2.log(string.concat("FT in market: ", formattedFtInMarket, " ", info.underlyingSymbol));
            console2.log(
                string.concat(
                    "Underlying of treasurer: ", formattedTreasurerUnderlyingBalance, " ", info.underlyingSymbol
                )
            );
            console2.log(string.concat("FT of treasurer: ", formattedTreasurerFtBalance, " ", info.underlyingSymbol));

            // Check if (FT total supply - FT in market) equals underlying in market
            if (info.ftTotalSupply > 0) {
                uint256 circulatingFT =
                    info.ftTotalSupply > info.ftInMarketBalance ? info.ftTotalSupply - info.ftInMarketBalance : 0;

                bool invariantPassed = circulatingFT == info.underlyingBalance;
                if (invariantPassed) {
                    console2.log("INVARIANT CHECK PASSED: (FT total supply - FT in market) equals underlying in market");
                } else {
                    console2.log(
                        "INVARIANT CHECK FAILED: (FT total supply - FT in market) does NOT equal underlying in market"
                    );
                    console2.log(
                        string.concat(
                            "  Expected: ",
                            formatTokenAmount(info.underlyingBalance, info.underlyingDecimals),
                            " ",
                            info.underlyingSymbol
                        )
                    );
                    console2.log(
                        string.concat(
                            "  Actual: ",
                            formatTokenAmount(circulatingFT, info.underlyingDecimals),
                            " ",
                            info.underlyingSymbol
                        )
                    );
                    console2.log(
                        string.concat(
                            "  Difference: ",
                            formatTokenAmount(
                                circulatingFT > info.underlyingBalance
                                    ? circulatingFT - info.underlyingBalance
                                    : info.underlyingBalance - circulatingFT,
                                info.underlyingDecimals
                            ),
                            " ",
                            info.underlyingSymbol
                        )
                    );
                }
            }

            // Check for active GT positions
            if (info.gt != address(0)) {
                try IGearingToken(info.gt).totalSupply() returns (uint256 totalSupply) {
                    if (totalSupply > 0) {
                        console2.log(string.concat("Positions (", vm.toString(totalSupply), " total):"));

                        // Check a few positions as example
                        uint256 positionsToCheck = totalSupply > 5 ? 5 : totalSupply;
                        for (uint256 j = 1; j <= positionsToCheck; j++) {
                            try IGearingToken(info.gt).loanInfo(j) returns (
                                address owner, uint128 debtAmt, bytes memory collateralData
                            ) {
                                // Get collateral amount from collateralData - assuming it's an abi encoded uint256
                                uint256 collateralAmt = 0;
                                if (collateralData.length >= 32) {
                                    collateralAmt = abi.decode(collateralData, (uint256));
                                }

                                string memory formattedDebt = formatTokenAmount(debtAmt, info.underlyingDecimals);
                                string memory formattedCollateral =
                                    formatTokenAmount(collateralAmt, info.collateralDecimals);

                                // Format position details without formatted string
                                string memory positionMsg = string.concat(
                                    "  Position ",
                                    vm.toString(j),
                                    ": Owner: ",
                                    formatAddress(owner),
                                    ", debt: ",
                                    formattedDebt,
                                    " ",
                                    info.underlyingSymbol,
                                    ", collateral: ",
                                    formattedCollateral,
                                    " ",
                                    info.collateralSymbol
                                );
                                console2.log(positionMsg);
                            } catch {
                                console2.log(string.concat("  Error fetching position ", vm.toString(j)));
                            }
                        }
                    } else {
                        console2.log("No active positions");
                    }
                } catch {
                    console2.log(string.concat("Error: Could not fetch GT positions for ", formatAddress(info.gt)));
                }
            }
        }
        console2.log("---------------------------------------------------------------");
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

    // Process market files and extract information
    function processMarketFiles(
        string memory deploymentDir,
        MarketInfo[] memory markets,
        bool dryRun,
        address treasurer
    ) internal {
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
                markets[marketIndex].fileName = files[i];

                // Extract market address
                markets[marketIndex].market = vm.parseJsonAddress(jsonContent, ".market");

                // Extract underlying and collateral addresses
                markets[marketIndex].underlying = vm.parseJsonAddress(jsonContent, ".underlying.address");
                markets[marketIndex].collateral = vm.parseJsonAddress(jsonContent, ".collateral.address");

                // Get tokens from market
                if (!dryRun) {
                    try ITermMaxMarket(markets[marketIndex].market).tokens() returns (
                        IMintableERC20 ft, IMintableERC20 xt, IGearingToken gt, address collateral, IERC20 underlying
                    ) {
                        markets[marketIndex].ft = address(ft);
                        markets[marketIndex].xt = address(xt);
                        markets[marketIndex].gt = address(gt);

                        // Double-check these match the JSON
                        if (collateral != markets[marketIndex].collateral) {
                            console2.log(string.concat("Warning: Collateral mismatch in ", files[i]));
                            console2.log(string.concat("  JSON: ", vm.toString(markets[marketIndex].collateral)));
                            console2.log(string.concat("  Market: ", vm.toString(collateral)));
                        }

                        if (address(underlying) != markets[marketIndex].underlying) {
                            console2.log(string.concat("Warning: Underlying mismatch in ", files[i]));
                            console2.log(string.concat("  JSON: ", vm.toString(markets[marketIndex].underlying)));
                            console2.log(string.concat("  Market: ", vm.toString(address(underlying))));
                        }
                    } catch (bytes memory err) {
                        console2.log(
                            string.concat(
                                "Error: Could not fetch tokens from market ",
                                formatAddress(markets[marketIndex].market),
                                ". Error: ",
                                err.length > 0 ? vm.toString(err) : "reverted without reason"
                            )
                        );
                    }
                } else {
                    // In dry-run mode, create dummy values based on file naming conventions
                    // Extract token symbols from filename (e.g. eth-mainnet-market-USDC-WBTC@02APR2025.json)
                    string memory fileNameWithoutPath = files[i];
                    // Extract market parts from filename
                    string[] memory parts = split(fileNameWithoutPath, "-");

                    if (parts.length >= 5) {
                        // Last part might contain something like "WBTC@02APR2025.json"
                        string[] memory symbolParts = split(parts[4], "@");
                        string[] memory suffixParts = split(symbolParts[0], ".");

                        markets[marketIndex].underlyingSymbol = parts[3]; // e.g. USDC
                        markets[marketIndex].collateralSymbol = suffixParts[0]; // e.g. WBTC

                        // Create dummy FT address in dry-run mode
                        markets[marketIndex].ft = address(uint160(0xFEED0000 + i));

                        // Set default values for dry-run mode
                        if (bytes(markets[marketIndex].underlyingSymbol).length == 0) {
                            markets[marketIndex].underlyingSymbol = "UNK";
                        }
                        if (bytes(markets[marketIndex].collateralSymbol).length == 0) {
                            markets[marketIndex].collateralSymbol = "UNK";
                        }

                        // Set dummy values for treasurer balances in dry-run mode
                        markets[marketIndex].treasurerUnderlyingBalance = 1000000 * (i + 1);
                        markets[marketIndex].treasurerFtBalance = 500000 * (i + 1);
                        markets[marketIndex].ftInMarketBalance = 200000 * (i + 1);
                        markets[marketIndex].underlyingDecimals = 6; // USDC is usually 6
                        markets[marketIndex].collateralDecimals = 18; // Most tokens are 18
                    }
                }

                // Get token symbols and decimals
                if (!dryRun) {
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
                }

                // Check balances
                if (!dryRun) {
                    try IERC20(markets[marketIndex].underlying).balanceOf(markets[marketIndex].market) returns (
                        uint256 balance
                    ) {
                        markets[marketIndex].underlyingBalance = balance;
                    } catch {
                        console2.log(
                            string.concat(
                                "Error: Could not fetch underlying balance for market ",
                                formatAddress(markets[marketIndex].market)
                            )
                        );
                    }

                    try IERC20(markets[marketIndex].collateral).balanceOf(markets[marketIndex].gt) returns (
                        uint256 balance
                    ) {
                        markets[marketIndex].collateralBalance = balance;
                    } catch {
                        console2.log(
                            string.concat(
                                "Error: Could not fetch collateral balance for GT ",
                                formatAddress(markets[marketIndex].gt)
                            )
                        );
                    }

                    // Check FT total supply
                    if (markets[marketIndex].ft != address(0)) {
                        try IERC20(markets[marketIndex].ft).totalSupply() returns (uint256 supply) {
                            markets[marketIndex].ftTotalSupply = supply;
                        } catch {
                            console2.log(
                                string.concat(
                                    "Error: Could not fetch FT total supply for ",
                                    formatAddress(markets[marketIndex].ft)
                                )
                            );
                        }

                        // Check FT balance in market
                        try IERC20(markets[marketIndex].ft).balanceOf(markets[marketIndex].market) returns (
                            uint256 balance
                        ) {
                            markets[marketIndex].ftInMarketBalance = balance;
                        } catch {
                            console2.log(
                                string.concat(
                                    "Error: Could not fetch FT balance in market ",
                                    formatAddress(markets[marketIndex].market)
                                )
                            );
                        }

                        // Check treasurer's FT balance
                        try IERC20(markets[marketIndex].ft).balanceOf(treasurer) returns (uint256 balance) {
                            markets[marketIndex].treasurerFtBalance = balance;
                        } catch {
                            console2.log(
                                string.concat(
                                    "Error: Could not fetch treasurer's FT balance for ",
                                    formatAddress(markets[marketIndex].ft)
                                )
                            );
                        }
                    }

                    // Check treasurer's underlying balance
                    try IERC20(markets[marketIndex].underlying).balanceOf(treasurer) returns (uint256 balance) {
                        markets[marketIndex].treasurerUnderlyingBalance = balance;
                    } catch {
                        console2.log(
                            string.concat(
                                "Error: Could not fetch treasurer's underlying balance for ",
                                formatAddress(markets[marketIndex].underlying)
                            )
                        );
                    }
                }

                marketIndex++;
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
        // Example fileName: eth-mainnet-market-USDC-WBTC@02APR2025.json
        // We want to extract: USDC-WBTC@02APR2025

        string[] memory parts = split(fileName, "market-");
        if (parts.length < 2) return fileName;

        string memory marketPart = parts[1];
        string[] memory jsonParts = split(marketPart, ".json");

        return jsonParts[0];
    }
}
