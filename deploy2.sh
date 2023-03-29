#!/bin/bash
DAT3='0xba6f578786f2ca745814d72b6240781680d85c1204f2253cbf5ad07ec3ee52a0'
echo "dat3:' $DAT3'"
DAT3_PATH=`pwd`
echo "aptos move compile -->  $DAT3_PATH --bytecode-version 6 "
echo `aptos move compile    --save-metadata --package-dir  $DAT3_PATH --bytecode-version 6 `
echo""
sleep 3
echo "aptos move publish -->  $DAT3_PATH --bytecode-version 6 "
echo `aptos move publish --profile test1  --assume-yes --package-dir  $DAT3_PATH --bytecode-version 6 `
echo""
sleep 5