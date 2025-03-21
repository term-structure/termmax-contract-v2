# Script Usage Guide

This guide explains how to use the deployment and script running utilities in the TermMax project.

## Deploy.sh

The `deploy.sh` script is used for deploying core contracts and market components.

### Usage

```bash
./deploy.sh <network> <type> [options]
```

### Parameters

- `network`: Target network for deployment
  - Supported networks: `eth-sepolia`, `arb-sepolia`, `eth-mainnet`, `arb-mainnet`
  
- `type`: Deployment type
  - Supported types: `core`, `market`, `order`, `vault`, `oracles`
  
- `options`: Additional flags
  - `--broadcast`: Execute the transactions on-chain (default is dry-run)
  - `--verify`: Enable contract verification

### Examples

```bash
# Dry run core deployment on Ethereum Sepolia
./deploy.sh eth-sepolia core

# Deploy market contracts on Arbitrum Sepolia
./deploy.sh arb-sepolia market --broadcast

# Submit oracles on Ethereum Mainnet
./deploy.sh eth-mainnet oracles --broadcast
```

## RunScript.sh

The `runScript.sh` utility is a more flexible script runner that can execute any Solidity script in the project.

### Usage

```bash
./runScript.sh <network> <script-name> [options]
```

### Parameters

- `network`: Target network for script execution
  - Supported networks: `eth-sepolia`, `arb-sepolia`, `eth-mainnet`, `arb-mainnet`
  
- `script-name`: Name of the script to run (without the .s.sol extension)
  - Example: `SubmitOracles` will run `SubmitOracles.s.sol`
  
- `options`: Additional flags
  - `--broadcast`: Execute the transactions on-chain (default is dry-run)
  - `--verify`: Enable contract verification (if applicable)

### Examples

```bash
# Run SubmitOracles script on Ethereum Sepolia (dry run)
./runScript.sh eth-sepolia SubmitOracles

# Run SubmitOracles script on Arbitrum Mainnet and broadcast transactions
./runScript.sh arb-mainnet SubmitOracles --broadcast

# Run E2ETest script on Arbitrum Sepolia 
./runScript.sh arb-sepolia E2ETest
```

## Special Environment Variables

Some scripts require specific environment variables:

### SubmitOracles Script

The `SubmitOracles` script requires an Oracle Aggregator Admin private key for each network:

```bash
# Required for eth-sepolia
ETH_SEPOLIA_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY=your_oracle_admin_private_key_here

# Required for eth-mainnet
ETH_MAINNET_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY=your_oracle_admin_private_key_here

# Required for arb-sepolia
ARB_SEPOLIA_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY=your_oracle_admin_private_key_here

# Required for arb-mainnet
ARB_MAINNET_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY=your_oracle_admin_private_key_here
```

This private key should belong to an account with admin privileges on the OracleAggregator contract.

## When to Use Each Script

1. Use `deploy.sh` for standard deployment workflows:
   - Core contracts 
   - Market components
   - Order contracts
   - Vault contracts

2. Use `runScript.sh` for:
   - Non-standard deployment scripts
   - Oracle submissions
   - Testing scripts
   - Other utility scripts

Both scripts require appropriate environment variables to be set in the `.env` file (see `.env.example` for reference). 