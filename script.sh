#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <network> <script-name> [options]"
    echo "Supported networks: eth-sepolia, arb-sepolia, eth-mainnet, arb-mainnet"
    echo "Script name: Name of the script file without extension (e.g., SubmitOracles)"
    echo "Options:"
    echo "  --broadcast     Broadcast transactions (default: dry run)"
    echo "  --verify       Enable contract verification"
    exit 1
fi

NETWORK=$1
SCRIPT_NAME=$2
shift 2  # Remove the first two arguments

# Default options (dry run without verification)
BROADCAST=""
VERIFY=""

# Parse remaining options
while [[ $# -gt 0 ]]; do
    case $1 in
        --broadcast)
            BROADCAST="--broadcast"
            shift
            ;;
        --verify)
            VERIFY="--verify"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate network
case $NETWORK in
    "eth-sepolia"|"arb-sepolia"|"eth-mainnet"|"arb-mainnet")
        echo "Running on $NETWORK..."
        ;;
    *)
        echo "Unsupported network: $NETWORK"
        echo "Supported networks: eth-sepolia, arb-sepolia, eth-mainnet, arb-mainnet"
        exit 1
        ;;
esac

# Convert network name to uppercase with underscores for env vars
NETWORK_UPPER=$(echo $NETWORK | tr '[:lower:]' '[:upper:]' | tr '-' '_')

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Get the RPC URL and other variables
RPC_URL_VAR="${NETWORK_UPPER}_RPC_URL"
DEPLOYER_PRIVATE_KEY_VAR="${NETWORK_UPPER}_DEPLOYER_PRIVATE_KEY"
ADMIN_ADDRESS_VAR="${NETWORK_UPPER}_ADMIN_ADDRESS"
ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY_VAR="${NETWORK_UPPER}_ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY"

# Additional variables for mainnet deployments
if [[ $NETWORK == *"mainnet"* ]]; then
    UNISWAP_V3_ROUTER_VAR="${NETWORK_UPPER}_UNISWAP_V3_ROUTER_ADDRESS"
    ODOS_V2_ROUTER_VAR="${NETWORK_UPPER}_ODOS_V2_ROUTER_ADDRESS"
    PENDLE_SWAP_V3_ROUTER_VAR="${NETWORK_UPPER}_PENDLE_SWAP_V3_ROUTER_ADDRESS"
    ORACLE_TIMELOCK_VAR="${NETWORK_UPPER}_ORACLE_TIMELOCK"
fi

RPC_URL="${!RPC_URL_VAR}"
DEPLOYER_PRIVATE_KEY="${!DEPLOYER_PRIVATE_KEY_VAR}"
ADMIN_ADDRESS="${!ADMIN_ADDRESS_VAR}"
ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY="${!ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY_VAR}"

# Check required environment variables
if [ -z "$RPC_URL" ]; then
    echo "Error: Required environment variable $RPC_URL_VAR is not set"
    exit 1
fi

if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "Error: Required environment variable $DEPLOYER_PRIVATE_KEY_VAR is not set"
    exit 1
fi

if [ -z "$ADMIN_ADDRESS" ]; then
    echo "Error: Required environment variable $ADMIN_ADDRESS_VAR is not set"
    exit 1
fi

# Check for Oracle Aggregator Admin Private Key when running SubmitOracles
if [ "$SCRIPT_NAME" = "SubmitOracles" ] && [ -z "$ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY" ]; then
    echo "Error: Required environment variable $ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY_VAR is not set"
    echo "This private key is required for the SubmitOracles script to function correctly."
    exit 1
fi

# Check additional required variables for mainnet deployments
if [[ $NETWORK == *"mainnet"* ]]; then
    if [ -z "${!UNISWAP_V3_ROUTER_VAR}" ]; then
        echo "Error: Required environment variable $UNISWAP_V3_ROUTER_VAR is not set"
        exit 1
    fi
    if [ -z "${!ODOS_V2_ROUTER_VAR}" ]; then
        echo "Error: Required environment variable $ODOS_V2_ROUTER_VAR is not set"
        exit 1
    fi
    if [ -z "${!PENDLE_SWAP_V3_ROUTER_VAR}" ]; then
        echo "Error: Required environment variable $PENDLE_SWAP_V3_ROUTER_VAR is not set"
        exit 1
    fi
    if [ -z "${!ORACLE_TIMELOCK_VAR}" ]; then
        echo "Error: Required environment variable $ORACLE_TIMELOCK_VAR is not set"
        exit 1
    fi
fi

echo "=== Script Configuration ==="
echo "Network: $NETWORK"
echo "Script: $SCRIPT_NAME.s.sol"
echo "RPC URL: $RPC_URL"
echo "Admin Address: $ADMIN_ADDRESS"
if [ "$SCRIPT_NAME" = "SubmitOracles" ]; then
    echo "Oracle Aggregator Admin: Using private key from $ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY_VAR"
fi
echo "Mode: ${BROADCAST:+Live Broadcast}${BROADCAST:-Dry Run}"
echo "Verification: ${VERIFY:+Enabled}${VERIFY:-Disabled}"
if [[ $NETWORK == *"mainnet"* ]]; then
    echo "Uniswap V3 Router: ${!UNISWAP_V3_ROUTER_VAR}"
    echo "Odos V2 Router: ${!ODOS_V2_ROUTER_VAR}"
    echo "Pendle Swap V3 Router: ${!PENDLE_SWAP_V3_ROUTER_VAR}"
    echo "Oracle Timelock: ${!ORACLE_TIMELOCK_VAR}"
fi
echo "==============================="

# Export the network name for the Solidity script
export NETWORK=$NETWORK

# Run the script
echo "Starting script execution..."

# Try to find the script in various locations
SCRIPT_LOCATIONS=(
    "script/deploy/${SCRIPT_NAME}.s.sol"
    "script/${SCRIPT_NAME}.s.sol"
    "script/utils/${SCRIPT_NAME}.s.sol"
)

SCRIPT_FOUND=false
for SCRIPT_PATH in "${SCRIPT_LOCATIONS[@]}"; do
    if [ -f "$SCRIPT_PATH" ]; then
        SCRIPT_FOUND=true
        break
    fi
done

if [ "$SCRIPT_FOUND" = false ]; then
    echo "Error: Script file not found. Searched in:"
    for SCRIPT_PATH in "${SCRIPT_LOCATIONS[@]}"; do
        echo "  - $SCRIPT_PATH"
    done
    exit 1
fi

# Build the forge command
if [ "$SCRIPT_NAME" = "SubmitOracles" ]; then
    FORGE_CMD="forge script $SCRIPT_PATH --private-key $ORACLE_AGGREGATOR_ADMIN_PRIVATE_KEY --rpc-url $RPC_URL"
else
    FORGE_CMD="forge script $SCRIPT_PATH --rpc-url $RPC_URL"
fi

# Add optional flags if specified
if [ ! -z "$BROADCAST" ]; then
    FORGE_CMD="$FORGE_CMD $BROADCAST --slow"
fi

if [ ! -z "$VERIFY" ]; then
    FORGE_CMD="$FORGE_CMD $VERIFY"
fi

# Execute the forge command
echo "Executing: $FORGE_CMD"
eval $FORGE_CMD

# Check if execution was successful
if [ $? -eq 0 ]; then
    if [ ! -z "$BROADCAST" ]; then
        echo "✅ Script $SCRIPT_NAME executed successfully on $NETWORK (Broadcast mode)!"
    else
        echo "✅ Script $SCRIPT_NAME dry run completed successfully on $NETWORK!"
    fi
else
    if [ ! -z "$BROADCAST" ]; then
        echo "❌ Script $SCRIPT_NAME execution failed on $NETWORK (Broadcast mode)!"
    else
        echo "❌ Script $SCRIPT_NAME dry run failed on $NETWORK!"
    fi
    exit 1
fi 