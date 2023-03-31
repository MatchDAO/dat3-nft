#!/bin/bash
DAT3='0x3e128ae33009e484f22b27fb5a043b8f056d0a944e6df221dd3f1c0041146cbf'
echo "dat3:' $DAT3'"
DAT3_PATH=`pwd`
echo "aptos move compile -->  $DAT3_PATH --bytecode-version 6 "
echo `aptos move compile    --save-metadata --package-dir  $DAT3_PATH --bytecode-version 6 `
echo""
sleep 3
echo "aptos move publish -->  $DAT3_PATH --bytecode-version 6 "
echo `aptos move publish --profile test3  --assume-yes --package-dir  $DAT3_PATH --bytecode-version 6 `
echo""
sleep 5