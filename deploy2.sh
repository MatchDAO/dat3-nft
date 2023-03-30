#!/bin/bash
DAT3='0xd8d80db601f7d8bc428c682bf3918806206625813fc634042276d93074615c13'
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