#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Usage: ./script/give_me_eth.sh 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    exit 1
fi

export MY_ADDRESS=$1

# account 0 from hardhat that has a lot of eth
export ETH_WHALE=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
# this allows us to impersonate our whales
cast rpc anvil_impersonateAccount $ETH_WHALE
cast send $MY_ADDRESS --unlocked --from $ETH_WHALE --value 100ether
