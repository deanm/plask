#!/bin/sh
NAME=deps_v4_2016_10_05
rm -rf deps
curl -L -O https://github.com/deanm/plask/releases/download/v4_2016-10-05/$NAME.tar.xz
tar xvf $NAME.tar.xz
#rm $NAME.tar.bz2
