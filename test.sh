#!/bin/bash
# for example: ./test.sh forktest
#              ./test.sh forktest LiquidationV2PtTest
#              ./test.sh forktest LiquidationV2PtTest -vvv
set -a
source env/$1.env
set +a

# get args from index 2
args=("${@:2}")

args_string=$(printf "%s " "${args[@]}")
forge test $args_string