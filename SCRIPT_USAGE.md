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
  - Supported types: `access-manager`, `core`, `market`, `order`, `vault`
  
- `options`: Additional flags
  - `--broadcast`: Execute the transactions on-chain (default is dry-run)
  - `--verify`: Enable contract verification

### Examples

```bash
# Dry run AccessManager deployment on Ethereum Sepolia
./deploy.sh eth-sepolia access-manager

# Deploy AccessManager on Ethereum Mainnet
./deploy.sh eth-mainnet access-manager --broadcast

# Dry run core deployment on Ethereum Sepolia
./deploy.sh eth-sepolia core

# Deploy market contracts on Arbitrum Sepolia
./deploy.sh arb-sepolia market --broadcast
```

## Script.sh

The `script.sh` utility is a more flexible script runner that can execute any Solidity script in the project.

### Usage

```bash
./script.sh <network> <script-name> [options]
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
# Deploy AccessManager contract on Ethereum Sepolia (dry run)
./script.sh eth-sepolia DeployAccessManager

# Deploy AccessManager contract on Ethereum Mainnet and broadcast transactions
./script.sh eth-mainnet DeployAccessManager --broadcast

# Grant roles to deployer address after AccessManager deployment
./script.sh eth-mainnet GrantRoles --broadcast

# Run SubmitOracles script on Ethereum Sepolia (dry run)
./script.sh eth-sepolia SubmitOracles

# Run SubmitOracles script on Arbitrum Mainnet and broadcast transactions
./script.sh arb-mainnet SubmitOracles --broadcast

# Run AcceptOracles script to accept pending oracles (after timelock period)
./script.sh eth-mainnet AcceptOracles --broadcast

# Run E2ETest script on Arbitrum Sepolia 
./script.sh arb-sepolia E2ETest
```

## Special Environment Variables

Some scripts require specific environment variables:

### GrantRoles Script

The `GrantRoles` script requires the admin's private key and the deployer's address for each network:

```bash
# Required for eth-sepolia
ETH_SEPOLIA_ADMIN_PRIVATE_KEY=your_admin_private_key_here
ETH_SEPOLIA_DEPLOYER_ADDRESS=your_deployer_address_here

# Required for eth-mainnet
ETH_MAINNET_ADMIN_PRIVATE_KEY=your_admin_private_key_here
ETH_MAINNET_DEPLOYER_ADDRESS=your_deployer_address_here

# Required for arb-sepolia
ARB_SEPOLIA_ADMIN_PRIVATE_KEY=your_admin_private_key_here
ARB_SEPOLIA_DEPLOYER_ADDRESS=your_deployer_address_here

# Required for arb-mainnet
ARB_MAINNET_ADMIN_PRIVATE_KEY=your_admin_private_key_here
ARB_MAINNET_DEPLOYER_ADDRESS=your_deployer_address_here
```

The admin private key should belong to the account that was specified as the initial admin during AccessManager deployment.

### SubmitOracles and AcceptOracles Scripts

Both the `SubmitOracles` and `AcceptOracles` scripts require an Oracle Aggregator Admin private key for each network:

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

#### Oracle Submission Process

The oracle update process consists of two steps:

1. **Submit Oracles**: Use the `SubmitOracles` script to submit new price feed oracles to the OracleAggregator contract.
   ```bash
   ./script.sh eth-mainnet SubmitOracles --broadcast
   ```

2. **Accept Oracles**: After the timelock period, use the `AcceptOracles` script to accept the pending oracles.
   ```bash
   ./script.sh eth-mainnet AcceptOracles --broadcast
   ```

## When to Use Each Script

1. Use `deploy.sh` for standard deployment workflows:
   - Core contracts 
   - Market components
   - Order contracts
   - Vault contracts
 
2. Use `script.sh` for:
   - Non-standard deployment scripts
   - Oracle submissions and acceptance
   - Testing scripts
   - Other utility scripts

Both scripts require appropriate environment variables to be set in the `.env` file (see `.env.example` for reference).

## Deployment Sequence

The correct deployment sequence is:

1. **Deploy AccessManager**: First, deploy the AccessManager which will manage permissions for all contracts.
   ```bash
   ./deploy.sh <network> access-manager --broadcast
   ```
   This creates a `<network>-access-manager.json` file containing the AccessManager address.

2. **Grant Roles to Deployer**: Use the admin account to grant necessary roles to the deployer address.
   ```bash
   ./script.sh <network> GrantRoles --broadcast
   ```
   This grants MARKET_ROLE, ORACLE_ROLE, VAULT_ROLE, and CONFIGURATOR_ROLE to the deployer address.

3. **Deploy Core Contracts**: Next, deploy the core contracts which will read the AccessManager address from the file.
   ```bash
   ./deploy.sh <network> core --broadcast
   ```
   This creates a `<network>-core.json` file containing all core contract addresses.

4. **Deploy Market Contracts**: Finally, deploy the market contracts which read from both JSON files.
   ```bash
   ./deploy.sh <network> market --broadcast
   ```

Following this sequence ensures that contracts are deployed with the correct dependency chain and permissions setup.