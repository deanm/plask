#!/bin/sh
NAME=deps_v4_002
rm -rf deps
curl -L -O https://googledrive.com/host/0B4M1ew30nMnnMFo2WVFrVDliU1U/$NAME.tar.xz
tar xvf $NAME.tar.xz
#rm $NAME.tar.bz2
