#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <network> <command> [options]"
    echo "Supported networks: eth-sepolia, arb-sepolia, eth-mainnet, arb-mainnet"
    echo ""
    echo "Commands:"
    echo "  1. Deployment Commands:"
    echo "     - deploy:access-manager  - Deploy Access Manager contract"
    echo "     - deploy:core            - Deploy Core contracts"
    echo "     - deploy:market          - Deploy Market contracts"
    echo "     - deploy:order           - Deploy Order contracts"
    echo "     - deploy:vault           - Deploy Vault contracts"
    echo ""
    echo "  2. Script Commands:"
    echo "     - script:<script-name>   - Run a custom script (e.g., script:GrantRoles, script:SubmitOracles)"
    echo ""
    echo "Options:"
    echo "  --broadcast     Broadcast transactions (default: dry run)"
    echo "  --verify        Enable contract verification"
    echo "  --tenderly      Enable verification on Tenderly"
    echo "  --debug         Show complete command with sensitive information (for debugging)"
    exit 1
fi

NETWORK=$1
COMMAND=$2
shift 2  # Remove the first two arguments

# Parse the command to determine if it's a deployment or a script
if [[ "$COMMAND" == deploy:* ]]; then
    OPERATION="deploy"
    TYPE=${COMMAND#deploy:}
elif [[ "$COMMAND" == script:* ]]; then
    OPERATION="script"
    SCRIPT_NAME=${COMMAND#script:}
else
    echo "Error: Invalid command format. Must be either 'deploy:<type>' or 'script:<script-name>'"
    exit 1
fi

# Default options (dry run without verification)
BROADCAST=""
VERIFY=""
TENDERLY=""
DEBUG=""

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
        --tenderly)
            TENDERLY="yes"
            shift
            ;;
        --debug)
            DEBUG="yes"
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

# If deploying, validate deployment type
if [ "$OPERATION" = "deploy" ]; then
    case $TYPE in
        "access-manager"|"core"|"market"|"order"|"vault")
            echo "Deployment type: $TYPE"
            ;;
        *)
            echo "Unsupported deployment type: $TYPE"
            echo "Supported deployment types: access-manager, core, market, order, vault"
            exit 1
            ;;
    esac
fi

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

# Check Tenderly environment variables if --tenderly is specified
if [ ! -z "$TENDERLY" ]; then
    if [ -z "$TENDERLY_VERIFIER_URL" ]; then
        echo "Error: Required environment variable TENDERLY_VERIFIER_URL is not set"
        exit 1
    fi
    
    if [ -z "$TENDERLY_ACCESS_KEY" ]; then
        echo "Error: Required environment variable TENDERLY_ACCESS_KEY is not set"
        exit 1
    fi
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

# Determine the script path and name
if [ "$OPERATION" = "deploy" ]; then
    # Capitalize first letter of type for script name
    if [ "$TYPE" = "access-manager" ]; then
        SCRIPT_NAME="DeployAccessManager"
    else
        TYPE_CAPITALIZED="$(tr '[:lower:]' '[:upper:]' <<< ${TYPE:0:1})${TYPE:1}"
        SCRIPT_NAME="Deploy${TYPE_CAPITALIZED}"
    fi
    
    # Define a fixed script path for deployments
    SCRIPT_PATH="script/deploy/${SCRIPT_NAME}.s.sol"
    
    # Check if the script exists
    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "Error: Deployment script not found: $SCRIPT_PATH"
        exit 1
    fi
else
    # For custom scripts, try multiple locations
    SCRIPT_LOCATIONS=(
        "script/deploy/${SCRIPT_NAME}.s.sol"
        "script/${SCRIPT_NAME}.s.sol"
        "script/utils/${SCRIPT_NAME}.s.sol"
    )

    SCRIPT_FOUND=false
    for POTENTIAL_SCRIPT_PATH in "${SCRIPT_LOCATIONS[@]}"; do
        if [ -f "$POTENTIAL_SCRIPT_PATH" ]; then
            SCRIPT_PATH=$POTENTIAL_SCRIPT_PATH
            SCRIPT_FOUND=true
            break
        fi
    done

    if [ "$SCRIPT_FOUND" = false ]; then
        echo "Error: Script file not found. Searched in:"
        for POTENTIAL_SCRIPT_PATH in "${SCRIPT_LOCATIONS[@]}"; do
            echo "  - $POTENTIAL_SCRIPT_PATH"
        done
        exit 1
    fi
fi

# Configuration summary
echo "=== Configuration ==="
if [ "$OPERATION" = "deploy" ]; then
    echo "Operation: Deployment"
    echo "Type: $TYPE"
else 
    echo "Operation: Script Execution"
fi
echo "Network: $NETWORK"
echo "Script: $SCRIPT_NAME.s.sol"
echo "Path: $SCRIPT_PATH"

# Mask the RPC URL to avoid exposing API keys
RPC_MASKED=$(echo "$RPC_URL" | sed -E 's/([a-zA-Z0-9]{4})[a-zA-Z0-9]*/\1*****/g')
echo "RPC URL: $RPC_MASKED"
echo "Admin Address: $ADMIN_ADDRESS"

echo "Mode: ${BROADCAST:+Live Broadcast}${BROADCAST:-Dry Run}"
echo "Verification: ${VERIFY:+Enabled}${VERIFY:-Disabled}"
echo "Tenderly Verification: ${TENDERLY:+Enabled}${TENDERLY:-Disabled}"
echo "Debug Mode: ${DEBUG:+Enabled}${DEBUG:-Disabled}"

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
if [ "$OPERATION" = "deploy" ]; then
    echo "Starting deployment..."
else
    echo "Starting script execution..."
fi

# Build the forge command
# All scripts, including SubmitOracles and AcceptOracles, use the DEPLOYER_PRIVATE_KEY
FORGE_CMD="forge script $SCRIPT_PATH --private-key $DEPLOYER_PRIVATE_KEY --rpc-url $RPC_URL"

# Add optional flags if specified
if [ ! -z "$BROADCAST" ]; then
    FORGE_CMD="$FORGE_CMD $BROADCAST --slow"
    
    # Add Tenderly verification if specified
    if [ ! -z "$TENDERLY" ]; then
        FORGE_CMD="$FORGE_CMD --verifier-url $TENDERLY_VERIFIER_URL --etherscan-api-key $TENDERLY_ACCESS_KEY"
    fi
fi

if [ ! -z "$VERIFY" ]; then
    FORGE_CMD="$FORGE_CMD $VERIFY"
fi

# When printing the forge command, check if debug mode is enabled
if [ ! -z "$DEBUG" ]; then
    echo "WARNING: Debug mode enabled. Displaying complete command with sensitive information:"
    echo "Executing: $FORGE_CMD"
else
    # Mask sensitive information in normal mode
    MASKED_CMD=$(echo "$FORGE_CMD" | sed -E 's/(--private-key )[^ ]*/\1[MASKED]/g' | sed -E 's/(--rpc-url )[^ ]*/\1[MASKED]/g' | sed -E 's/(--verifier-url )[^ ]*/\1[MASKED]/g' | sed -E 's/(--etherscan-api-key )[^ ]*/\1[MASKED]/g')
    echo "Executing: $MASKED_CMD"
fi

eval $FORGE_CMD

# Check if execution was successful
if [ $? -eq 0 ]; then
    if [ ! -z "$BROADCAST" ]; then
        if [ "$OPERATION" = "deploy" ]; then
            echo "[SUCCESS] ${TYPE} deployment to $NETWORK completed successfully!"
        else
            echo "[SUCCESS] Script $SCRIPT_NAME executed successfully on $NETWORK (Broadcast mode)!"
        fi
    else
        if [ "$OPERATION" = "deploy" ]; then
            echo "[SUCCESS] ${TYPE} dry run on $NETWORK completed successfully!"
        else
            echo "[SUCCESS] Script $SCRIPT_NAME dry run completed successfully on $NETWORK!"
        fi
    fi
else
    if [ ! -z "$BROADCAST" ]; then
        if [ "$OPERATION" = "deploy" ]; then
            echo "[ERROR] ${TYPE} deployment to $NETWORK failed!"
        else
            echo "[ERROR] Script $SCRIPT_NAME execution failed on $NETWORK (Broadcast mode)!"
        fi
    else
        if [ "$OPERATION" = "deploy" ]; then
            echo "[ERROR] ${TYPE} dry run on $NETWORK failed!"
        else
            echo "[ERROR] Script $SCRIPT_NAME dry run failed on $NETWORK!"
        fi
    fi
    exit 1
fi 