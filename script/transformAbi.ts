import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

// List of JSON files to transform
const contractFiles = [
  './out/Faucet.sol/Faucet.json',
  './out/TermMaxRouter.sol/TermMaxRouter.json',
  './out/MintableERC20.sol/MintableERC20.json',
  './out/GearingTokenWithERC20.sol/GearingTokenWithERC20.json',
  './out/TermMaxMarket.sol/TermMaxMarket.json',
  './out/TermMaxOrder.sol/TermMaxOrder.json',
  './out/TermMaxVault.sol/TermMaxVault.json',
  './out/VaultFactory.sol/VaultFactory.json',
  './out/OracleAggregator.sol/OracleAggregator.json',
  './out/TermMaxFactory.sol/TermMaxFactory.json',
];

const transformAbi = (filePath: string) => {
  try {
    // Read and parse the JSON file
    const contractJson = JSON.parse(readFileSync(filePath, 'utf-8'));

    // Format the ABI
    const formattedAbi = JSON.stringify(contractJson.abi, null, 2)
      .replace(/"(\w+)":/g, '$1:') // Remove quotes from keys
      .replace(/"/g, "'") // Replace double quotes with single quotes
      .replace(/([^,{[])(\n\s*[}\]])/g, '$1,$2') // Add trailing commas
      .replace(/(})(\n\s*])/g, '$1,$2'); // Ensure {} inside arrays get trailing commas

    // Extract contract name from path (e.g., Faucet.json -> Faucet)
    const contractName = filePath.split('/').pop()?.replace('.json', '') || 'Contract';

    // Define TypeScript content
    const tsContent = `// This file is auto-generated. Do not edit manually.\n\nexport const abi${contractName} = ${formattedAbi} as const;\n`;

    // Define output filename
    const outputFileName = join('./abi_typescript', `abi${contractName}.ts`);

    // Write the transformed TypeScript file
    writeFileSync(outputFileName, tsContent);
    console.log(`ABI transformed successfully: ${outputFileName}`);
  } catch (error) {
    console.error(`Error processing ${filePath}:`, error);
  }
};

// Process all contract files
contractFiles.forEach(transformAbi);
