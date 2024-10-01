#!/bin/bash
# for example: ./script.sh netenvname script/xxx.sol verify
#              ./script.sh netenvname script/xxx.sol
# ./script.sh arbsepolia script/DeployAmazingliquidator.sol verify
set -a
source env/$1.env
set +a

if [ "$3" = "verify" ]&&[ -n "$VERIFIER_URL" ]&&[ -n "$ETHERSCAN_KEY" ]; then
    echo "run script and verify contracts on: $1"
    # excute your script
    forge script $2 --broadcast --verify --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_KEY --verifier-url $VERIFIER_URL --slow
else
    echo "run script on: $1"
    forge script $2 --broadcast --rpc-url $RPC_URL
fi
