#!/bin/bash
# for example: ./script.sh netenvname script/xxx.sol verify
#              ./script.sh netenvname script/xxx.sol
# ./script.sh arbsepolia script/DeployAmazingliquidator.sol verify
# ./deploy.sh arbSepolia core
# ./deploy.sh arbSepolia market
source .env

current_date=$(date "+%Y-%m-%d:%H:%M:%S")

# Ensure correct spacing and syntax in condition checks
if [ "$1" == "ArbSepolia" ]; then
  RPC_URL=$ARB_SEPOLIA_RPC_URL
  EXPLORER_KEY=$ARBISCAN_KEY
elif [ "$1" == "EthSepolia" ]; then
  RPC_URL=$ETH_SEPOLIA_RPC_URL
  EXPLORER_KEY=$ETHERSCAN_KEY
elif [ "$1" == "Holesky" ]; then
  RPC_URL=$HOLESKY_RPC_URL
  EXPLORER_KEY=$ETHERSCAN_KEY
else
  echo "Invalid network"
  exit 1
fi

if [ "$2" == "core" ]; then
  SCRIPT=script/deploy/$1/DeployCore$1.s.sol
elif [ "$2" == "market" ]; then
  SCRIPT=script/deploy/$1/DeployMarket$1.s.sol
else
  echo "Invalid script type"
  exit 1
fi

if [ "$3" == "broadcast" ]; then
  if [ "$4" == "verify" ] && [ -n "$EXPLORER_KEY" ]; then
    echo "Deploy and verify $2 contracts on $1"
    # Execute the script with verification
    forge script $SCRIPT --broadcast --verify --rpc-url $RPC_URL --etherscan-api-key $EXPLORER_KEY --slow > log/deploy_$1_$2_$current_date.log
  else
    echo "Deploy $2 contracts on $1"
    forge script $SCRIPT --broadcast --rpc-url $RPC_URL > log/deploy_$1_$2_$current_date.log
  fi
else
  echo "[Simulation] Deploy $2 contracts on $1"
  forge script $SCRIPT --rpc-url $RPC_URL 
fi



# if [ "$3" = "verify" ]&&[ -n "$VERIFIER_URL" ]&&[ -n "$ETHERSCAN_KEY" ]; then
#     echo "run script and verify contracts on: $1"
#     # excute your script
#     forge script $2 --broadcast --verify --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_KEY --verifier-url $VERIFIER_URL --slow
# else
#     echo "run script on: $1"
#     forge script $2 --broadcast --rpc-url $RPC_URL
# fi
