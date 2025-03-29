import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse/sync';
import { DeployConfig, MarketData } from './utils/types';

// Parse command line arguments
const args = process.argv.slice(2);

// Check if required arguments are provided
if (args.length < 2) {
    console.error('Usage: ts-node script/convertMarketConfigs.ts <input-csv-path> <output-json-path>');
    console.error('Example: ts-node script/convertMarketConfigs.ts script/deploy/deploydata/eth-mainnet.csv script/deploy/deploydata/eth-mainnet.json');
    process.exit(1);
}

const inputCsvPath = args[0];
const outputJsonPath = args[1];

// Read the CSV file
console.log(`Reading CSV from: ${inputCsvPath}`);
const csvContent = fs.readFileSync(inputCsvPath, 'utf-8');

// Parse CSV
const records = parse(csvContent, {
    columns: (headers: string[]) => {
        // Skip the first row (which contains section headers)
        return headers.map((header, index) => {
            // Map the columns based on their position
            switch (index) {
                case 0: return 'marketType';
                case 1: return 'salt';
                case 2: return 'collateralCapForGt';
                case 3: return 'maturity';
                case 4: return 'lendTakerFeeRatio';
                case 5: return 'lendMakerFeeRatio';
                case 6: return 'borrowTakerFeeRatio';
                case 7: return 'borrowMakerFeeRatio';
                case 8: return 'mintGtFeeRatio';
                case 9: return 'mintGtFeeRef';
                case 10: return 'liquidationLtv';
                case 11: return 'maxLtv';
                case 12: return 'liquidatable';
                case 13: return 'underlyingTokenAddr';
                case 14: return 'underlyingPriceFeedAddr';
                case 15: return 'underlyingHeartBeat';
                case 16: return 'underlyingName';
                case 17: return 'underlyingSymbol';
                case 18: return 'underlyingDecimals';
                case 19: return 'underlyingInitialPrice';
                case 20: return 'collateralTokenAddr';
                case 21: return 'collateralPriceFeedAddr';
                case 22: return 'collateralHeartBeat';
                case 23: return 'collateralName';
                case 24: return 'collateralSymbol';
                case 25: return 'collateralDecimals';
                case 26: return 'collateralInitialPrice';
                case 27: return 'gtKeyIdentifier';
                // Skip the note column (28) by not mapping it
                default: return `column${index}`;
            }
        });
    },
    skip_empty_lines: true,
    trim: true,
    from: 2 // Skip the first row (section headers)
});

// Convert to required format
const deployConfig: DeployConfig = {
    configNum: records.length.toString(),
    configs: {}
};

// Parse number with commas to a clean string
function parseNumberWithCommas(value: string): string {
    if (!value) return ""; // Return empty string instead of default value
    // Remove all commas and non-numeric characters except decimal point
    return value.replace(/,/g, '').trim();
}

records.forEach((record: any, index: number) => {
    try {
        // console.log(`Processing record ${index + 1}...`);

        // Debug log column names for the first record
        if (index === 0) {
            console.log('CSV Column Headers:', Object.keys(record));
        }

        // Parse collateralCapForGt (remove commas)
        const collateralCapForGt = parseNumberWithCommas(record['collateralCapForGt']);

        // Use the gtKeyIdentifier directly from CSV
        // Default to "GearingTokenWithERC20" if not provided
        const gtKeyIdentifier = record['gtKeyIdentifier'] || "GearingTokenWithERC20";

        const marketData: MarketData = {
            salt: parseInt(record['salt'] || '0'),
            collateralCapForGt: collateralCapForGt,
            marketConfig: {
                maturity: record['maturity'] || '',
                lendTakerFeeRatio: record['lendTakerFeeRatio'] || '',
                lendMakerFeeRatio: record['lendMakerFeeRatio'] || '',
                borrowTakerFeeRatio: record['borrowTakerFeeRatio'] || '',
                borrowMakerFeeRatio: record['borrowMakerFeeRatio'] || '',
                mintGtFeeRatio: record['mintGtFeeRatio'] || '',
                mintGtFeeRef: record['mintGtFeeRef'] || ''
            },
            loanConfig: {
                liquidationLtv: record['liquidationLtv'] || '',
                maxLtv: record['maxLtv'] || '',
                liquidatable: (record['liquidatable'] || '').toUpperCase() === 'TRUE'
            },
            underlyingConfig: {
                tokenAddr: record['underlyingTokenAddr'] || '',
                priceFeedAddr: record['underlyingPriceFeedAddr'] || '',
                heartBeat: record['underlyingHeartBeat'] || '86400',
                name: record['underlyingName'] || '',
                symbol: record['underlyingSymbol'] || '',
                decimals: record['underlyingDecimals'] || '',
                initialPrice: convertToBaseUnit(record['underlyingInitialPrice'] || '0')
            },
            collateralConfig: {
                tokenAddr: record['collateralTokenAddr'] || '',
                priceFeedAddr: record['collateralPriceFeedAddr'] || '',
                heartBeat: record['collateralHeartBeat'] || '3600',
                name: record['collateralName'] || '',
                symbol: record['collateralSymbol'] || '',
                decimals: record['collateralDecimals'] || '',
                initialPrice: convertToBaseUnit(record['collateralInitialPrice'] || '0'),
                gtKeyIdentifier: gtKeyIdentifier
            }
        };

        // Add market name and symbol (derived from tokens)
        const collateralSymbol = record['collateralSymbol'] || '';
        const underlyingSymbol = record['underlyingSymbol'] || '';
        const maturity = record['maturity'] || '';

        // Convert timestamp to human readable date format (DDMMMYYYY)
        const maturityDate = new Date(parseInt(maturity) * 1000);
        const day = maturityDate.getUTCDate().toString().padStart(2, '0');
        const month = maturityDate.toLocaleString('en-US', { month: 'short' }).toUpperCase();
        const year = maturityDate.getUTCFullYear();
        const formattedDate = `${day}${month}${year}`;

        marketData.marketName = `${underlyingSymbol}/${collateralSymbol}-${formattedDate}`;
        marketData.marketSymbol = `${underlyingSymbol}/${collateralSymbol}-${formattedDate}`;

        // Debug log for the first record
        if (index === 0) {
            console.log('First record data:', record);
            console.log('Processed market data:', marketData);
            console.log('Price Feed Addresses:');
            console.log(`Underlying Price Feed: ${record['underlyingPriceFeedAddr']}`);
            console.log(`Collateral Price Feed: ${record['collateralPriceFeedAddr']}`);
            console.log('Heartbeat Values:');
            console.log(`Underlying Heartbeat: ${record['underlyingHeartBeat'] || '86400'} (default: 86400 if not specified)`);
            console.log(`Collateral Heartbeat: ${record['collateralHeartBeat'] || '3600'} (default: 3600 if not specified)`);
        }
        const collateralCapAmt = BigInt(collateralCapForGt || '0') / (BigInt(10) ** BigInt(parseInt(record['collateralDecimals'] || '18')));
        const collateralCapVault = BigInt(collateralCapForGt || '0') * BigInt(parseInt(convertToBaseUnit(record['collateralInitialPrice'] || '0'))) / (BigInt(10) ** BigInt(parseInt(record['collateralDecimals'] || '18'))) / BigInt(10 ** 8);
        console.log(`Collateral Symbol:`, record['collateralSymbol']);
        console.log(`Collateral Initial Price:`, record['collateralInitialPrice']);
        console.log(`Collateral Cap Amt:`, collateralCapAmt);
        console.log(`Collateral Cap Vault: ${collateralCapVault}`);

        deployConfig.configs[`configs_${index}`] = marketData;
    } catch (error) {
        console.error(`Error processing record ${index + 1}:`, error);
        console.error('Record data:', record);
        throw error;
    }
});

// Helper function to convert price to base units with 8 decimals
function convertToBaseUnit(price: string): string {
    try {
        const priceNum = parseFloat(price);
        if (isNaN(priceNum)) {
            console.warn(`Warning: Invalid price (${price}), using 0`);
            return '0';
        }
        const PRICE_DECIMALS = 8; // Always use 8 decimals for prices
        const multiplier = Math.pow(10, PRICE_DECIMALS);
        const result = Math.floor(priceNum * multiplier);
        // Convert to string and ensure it's in full decimal notation
        return result.toLocaleString('fullwide', { useGrouping: false });
    } catch (error) {
        console.error('Error converting price to base units:', error);
        return '0';
    }
}

// Create directory if it doesn't exist
const outputDir = path.dirname(outputJsonPath);
if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
}

// Write to JSON file
fs.writeFileSync(
    outputJsonPath,
    JSON.stringify(deployConfig, null, 2),
    'utf-8'
);

console.log(`Conversion complete. Output written to ${outputJsonPath}`);