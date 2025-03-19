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
                case 2: return 'treasur';
                case 3: return 'maturity';
                case 4: return 'lendTakerFeeRatio';
                case 5: return 'lendMakerFeeRatio';
                case 6: return 'borrowTakerFeeRatio';
                case 7: return 'borrowMakerFeeRatio';
                case 8: return 'issueFtFeeRatio';
                case 9: return 'issueFtFeeRef';
                case 10: return 'redeemFeeRatio';
                case 11: return 'liquidationLtv';
                case 12: return 'maxLtv';
                case 13: return 'liquidatable';
                case 14: return 'underlyingTokenAddr';
                case 15: return 'underlyingName';
                case 16: return 'underlyingSymbol';
                case 17: return 'underlyingDecimals';
                case 18: return 'underlyingInitialPrice';
                case 19: return 'collateralTokenAddr';
                case 20: return 'collateralName';
                case 21: return 'collateralSymbol';
                case 22: return 'collateralDecimals';
                case 23: return 'collateralInitialPrice';
                case 24: return 'gtKeyIdentifier';
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

records.forEach((record: any, index: number) => {
    try {
        console.log(`Processing record ${index + 1}...`);
        
        // Debug log
        if (index === 0) {
            console.log('CSV Column Headers:', Object.keys(record));
        }

        const marketData: MarketData = {
            salt: parseInt(record['salt'] || '0'),
            marketConfig: {
                treasurer: record['treasur']?.replace(/["""]/g, '') || '',
                maturity: record['maturity'] || '',
                lendTakerFeeRatio: record['lendTakerFeeRatio'] || '',
                lendMakerFeeRatio: record['lendMakerFeeRatio'] || '',
                borrowTakerFeeRatio: record['borrowTakerFeeRatio'] || '',
                borrowMakerFeeRatio: record['borrowMakerFeeRatio'] || '',
                issueFtFeeRatio: record['issueFtFeeRatio'] || '',
                issueFtFeeRef: record['issueFtFeeRef'] || '',
                redeemFeeRatio: record['redeemFeeRatio'] || '0'
            },
            loanConfig: {
                liquidationLtv: record['liquidationLtv'] || '',
                maxLtv: record['maxLtv'] || '',
                liquidatable: (record['liquidatable'] || '').toUpperCase() === 'TRUE'
            },
            underlyingConfig: {
                tokenAddr: record['underlyingTokenAddr'] || '',
                name: record['underlyingName'] || '',
                symbol: record['underlyingSymbol'] || '',
                decimals: record['underlyingDecimals'] || '',
                initialPrice: convertToBaseUnit(record['underlyingInitialPrice'] || '0')
            },
            collateralConfig: {
                tokenAddr: record['collateralTokenAddr'] || '',
                name: record['collateralName'] || '',
                symbol: record['collateralSymbol'] || '',
                decimals: record['collateralDecimals'] || '',
                initialPrice: convertToBaseUnit(record['collateralInitialPrice'] || '0'),
                gtKeyIdentifier: record['gtKeyIdentifier'] || ''
            }
        };

        // Debug log for the first record
        if (index === 0) {
            console.log('First record data:', record);
            console.log('Processed market data:', marketData);
        }

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