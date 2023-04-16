#!/bin/bash
DAT3='0x0ecae460da5f09e6568e804e9dd56123f1d776281893ba86db903c8078a58776'
PROFILE="nft_v2"
echo "dat3:' $DAT3'"
BASE_PATH=`pwd `
DAT3_COIN="$BASE_PATH/dat3-coin"
DAT3_CORE="$BASE_PATH/dat3-core"
DAT3_T_INTERFACE="$BASE_PATH/interface"
DAT3_STAKING="$BASE_PATH/staking"
cd ..
DAT3_POOL="`pwd`/dat3-contract-core"
DAT3_NFT="`pwd`/dat3-nft"
echo "aptos move compile -->  $DAT3_NFT  "
echo `aptos move compile --save-metadata --package-dir  $DAT3_NFT  --bytecode-version 6`
echo""
sleep 3
#echo "aptos move publish --> $DAT3_NFT   "
# echo `aptos move publish --profile $PROFILE --assume-yes --package-dir  $DAT3_NFT --bytecode-version 6 `
#echo""
echo "aptos move publish --> $DAT3_NFT   "
 #echo `aptos move publish --profile $PROFILE --assume-yes --package-dir  $DAT3_NFT --bytecode-version 6 `
echo `aptos move publish --profile  $PROFILE   --assume-yes --package-dir  $DAT3_NFT --bytecode-version 6 `
echo""