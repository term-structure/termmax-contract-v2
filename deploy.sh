#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <network> <type> [options]"
    echo "Supported networks: eth-sepolia, arb-sepolia, eth-mainnet, arb-mainnet"
    echo "Deployment types: access-manager, core, market, order, vault, access-manager-v2, core-v2"
    echo "Options:"
    echo "  --broadcast     Broadcast transactions (default: dry run)"
    echo "  --verify       Enable contract verification"
    exit 1
fi

NETWORK=$1
TYPE=$2
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
    "eth-sepolia"|"arb-sepolia"|"eth-mainnet"|"arb-mainnet"|"bnb-mainnet")
        echo "Deploying to $NETWORK..."
        ;;
    *)
        echo "Unsupported network: $NETWORK"
        echo "Supported networks: eth-sepolia, arb-sepolia, eth-mainnet, arb-mainnet, bnb-mainnet"
        exit 1
        ;;
esac

# Validate deployment type
case $TYPE in
    "access-manager"|"core"|"market"|"order"|"vault"|"access-manager-v2"|"core-v2")
        echo "Deployment type: $TYPE"
        ;;
    *)
        echo "Unsupported deployment type: $TYPE"
        echo "Supported types: access-manager, core, market, order, vault, access-manager-v2, core-v2"
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

# Capitalize first letter of type for script name
if [ "$TYPE" = "access-manager" ]; then
    SCRIPT_NAME="DeployAccessManager"
elif [ "$TYPE" = "access-manager-v2" ]; then
    SCRIPT_NAME="DeployAccessManagerV2"
elif [ "$TYPE" = "core-v2" ]; then
    SCRIPT_NAME="DeployCoreV2"
else
    TYPE_CAPITALIZED="$(tr '[:lower:]' '[:upper:]' <<< ${TYPE:0:1})${TYPE:1}"
    SCRIPT_NAME="Deploy${TYPE_CAPITALIZED}"
fi

echo "=== Deployment Configuration ==="
echo "Network: $NETWORK"
echo "Type: $TYPE"
echo "Script: ${SCRIPT_NAME}.s.sol"
# Mask the RPC URL to avoid exposing API keys
RPC_MASKED=$(echo "$RPC_URL" | sed -E 's/([a-zA-Z0-9]{4})[a-zA-Z0-9]*/\1*****/g')
echo "RPC URL: $RPC_MASKED"
echo "Admin Address: $ADMIN_ADDRESS"
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

# Run the deployment
echo "Starting deployment..."
SCRIPT_PATH="script/deploy/${SCRIPT_NAME}.s.sol"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Script file not found: $SCRIPT_PATH"
    exit 1
fi

# Build the forge command
FORGE_CMD="forge script $SCRIPT_PATH --rpc-url $RPC_URL"

# Add optional flags if specified
if [ ! -z "$BROADCAST" ]; then
    FORGE_CMD="$FORGE_CMD $BROADCAST --slow"
fi

if [ ! -z "$VERIFY" ]; then
    FORGE_CMD="$FORGE_CMD $VERIFY"
fi

# Execute the forge command
echo "Executing: $(echo "$FORGE_CMD" | sed -E 's/(--rpc-url )[^ ]*/\1[MASKED]/g')"
eval $FORGE_CMD

# Check if deployment was successful
if [ $? -eq 0 ]; then
    if [ ! -z "$BROADCAST" ]; then
        echo "✅ ${TYPE_CAPITALIZED} deployment to $NETWORK completed successfully!"
    else
        echo "✅ ${TYPE_CAPITALIZED} dry run on $NETWORK completed successfully!"
    fi
else
    if [ ! -z "$BROADCAST" ]; then
        echo "❌ ${TYPE_CAPITALIZED} deployment to $NETWORK failed!"
    else
        echo "❌ ${TYPE_CAPITALIZED} dry run on $NETWORK failed!"
    fi
    exit 1
fi