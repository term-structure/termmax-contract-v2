#!/bin/bash
set -a
source env/$1.env
set +a

# get args from index 2
args=("${@:2}")

args_string=$(printf "%s " "${args[@]}")
forge coverage --ir-minimum $args_string