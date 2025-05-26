# Script Usage Guide

This guide explains how to use the unified script execution utility in the TermMax project.

## Script.sh

The `script.sh` utility is a flexible command runner that can handle both deployments and script execution in a unified way.

### Usage

```bash
./script.sh <network> <command> [options]
```

### Parameters

- `network`: Target network for deployment or script execution
  - Supported networks: `eth-sepolia`, `arb-sepolia`, `eth-mainnet`, `arb-mainnet`
  
- `command`: Command type and name, using the format `type:name`
  - Deployment commands: 
    - `deploy:access-manager` - Deploy Access Manager
    - `deploy:core` - Deploy Core contracts
    - `deploy:market` - Deploy Market contracts
    - `deploy:order` - Deploy Order contracts
    - `deploy:vault` - Deploy Vault contracts
    - `deploy:pretmx` - Deploy PreTMX token contract
  - Script commands:
    - `script:<script-name>` - Run a custom script (e.g., `script:GrantRoles`, `script:SubmitOracles`)
  
- `options`: Additional flags
  - `--broadcast`: Execute the transactions on-chain (default is dry-run)
  - `--verify`: Enable contract verification

### Examples

```bash
# Deploy AccessManager contract on Ethereum Sepolia (dry run)
./script.sh eth-sepolia deploy:access-manager

# Deploy AccessManager contract on Ethereum Mainnet and broadcast transactions
./script.sh eth-mainnet deploy:access-manager --broadcast

# Deploy core contracts on Ethereum Sepolia (dry run)
./script.sh eth-sepolia deploy:core

# Deploy market contracts on Arbitrum Sepolia with broadcasting
./script.sh arb-sepolia deploy:market --broadcast

# Deploy order contract on Arbitrum Sepolia
./script.sh arb-sepolia deploy:order --broadcast

# Grant roles to deployer address after AccessManager deployment
./script.sh eth-mainnet script:GrantRoles --broadcast

# Run SubmitOracles script on Ethereum Sepolia (dry run)
./script.sh eth-sepolia script:SubmitOracles

# Run SubmitOracles script on Arbitrum Mainnet and broadcast transactions
./script.sh arb-mainnet script:SubmitOracles --broadcast

# Run AcceptOracles script to accept pending oracles (after timelock period)
./script.sh eth-mainnet script:AcceptOracles --broadcast

# Run E2ETest script on Arbitrum Sepolia 
./script.sh arb-sepolia script:E2ETest

# Deploy PreTMX token contract on Ethereum Sepolia (dry run)
./script.sh eth-sepolia deploy:pretmx

# Deploy PreTMX token contract on Arbitrum Mainnet and broadcast transactions
./script.sh arb-mainnet deploy:pretmx --broadcast

# Deploy PreTMX token contract with verification on Ethereum Mainnet
./script.sh eth-mainnet deploy:pretmx --broadcast --verify
```

## System Setup Flow

The proper sequence for setting up the TermMax system is as follows:

1. **Deploy AccessManager**: First, deploy the AccessManager which will manage permissions for all contracts.
   ```bash
   ./script.sh <network> deploy:access-manager --broadcast
   ```
   This creates a `<network>-access-manager.json` file containing the AccessManager address.

2. **Grant Roles to Deployer**: Use the admin account to grant necessary roles to the deployer address.
   ```bash
   ./script.sh <network> script:GrantRoles --broadcast
   ```
   This grants MARKET_ROLE, ORACLE_ROLE, VAULT_ROLE, and CONFIGURATOR_ROLE to the deployer address.

3. **Deploy Core Contracts**: Next, deploy the core contracts which will read the AccessManager address from the file.
   ```bash
   ./script.sh <network> deploy:core --broadcast
   ```
   This creates a `<network>-core.json` file containing all core contract addresses.

4. **Submit Oracles**: Configure price feed oracles by submitting them to the OracleAggregator contract.
   ```bash
   ./script.sh <network> script:SubmitOracles --broadcast
   ```

5. **Accept Oracles**: After the timelock period, accept the pending oracles.
   ```bash
   ./script.sh <network> script:AcceptOracles --broadcast
   ```

6. **Deploy Market Contracts**: Deploy the market contracts which read from both JSON files.
   ```bash
   ./script.sh <network> deploy:market --broadcast
   ```

7. **Deploy Order Contracts**: Create orders for the market.
   ```bash
   ./script.sh <network> deploy:order --broadcast
   ```

8. **Deploy Vault Contracts**: Finally, deploy the vault contracts.
   ```bash
   ./script.sh <network> deploy:vault --broadcast
   ```

Following this sequence ensures that contracts are deployed with the correct dependency chain and permissions setup.

## PreTMX Token Deployment

The PreTMX token can be deployed independently of the main system flow as it's a standalone tokenomics contract:

```bash
# Deploy PreTMX token contract
./script.sh <network> deploy:pretmx --broadcast
```

This creates a `<network>-pretmx.json` file containing the PreTMX token contract details.

### PreTMX Token Features

- **Token Name**: "Pre TermMax Token"
- **Symbol**: "pTMX"
- **Initial Supply**: 1,000,000,000 tokens (1e9 ether)
- **Access Control**: Uses `Ownable2Step` for secure ownership transfer
- **Transfer Restrictions**: Transfers are initially restricted and require whitelisting
- **Initial State**: Admin is whitelisted for both sending and receiving transfers

### Post-Deployment Management

After deployment, the admin can manage the token through the following functions:

1. **Transfer Restrictions**:
   - `enableTransfer()` - Remove all transfer restrictions
   - `disableTransfer()` - Re-enable transfer restrictions

2. **Whitelist Management**:
   - `whitelistTransferFrom(address, bool)` - Allow/disallow an address to send tokens
   - `whitelistTransferTo(address, bool)` - Allow/disallow an address to receive tokens

3. **Token Operations**:
   - `mint(address, uint256)` - Mint additional tokens (admin only)
   - `burn(uint256)` - Burn tokens (any token holder)

4. **Ownership Transfer** (Two-step process for security):
   - `transferOwnership(address)` - Initiate ownership transfer
   - New owner calls `acceptOwnership()` - Complete the transfer

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

### DeployOrder Script

The `DeployOrder` script requires market addresses to be either:
1. Provided via environment variables (`{NETWORK}_MARKET_ADDRESS`)
2. Found in the deployment files (`deployments/{network}/{network}-market.json`)
3. For Arbitrum Sepolia, a default address is hardcoded

### SubmitOracles and AcceptOracles Scripts

Both the `SubmitOracles` and `AcceptOracles` scripts use the deployer private key that has been granted the necessary roles through the `GrantRoles` script.

#### Oracle Submission Process

The oracle update process consists of two steps:

1. **Submit Oracles**: Use the `SubmitOracles` script to submit new price feed oracles to the OracleAggregator contract.
   ```bash
   ./script.sh <network> script:SubmitOracles --broadcast
   ```

2. **Accept Oracles**: After the timelock period, use the `AcceptOracles` script to accept the pending oracles.
   ```bash
   ./script.sh <network> script:AcceptOracles --broadcast
   ```