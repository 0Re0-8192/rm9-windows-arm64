#!/bin/bash
P=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg
ls $P
echo "== how QcomPkg blobs are pulled in"
grep -n "QcomPkg" $P/*.dsc $P/*.fdf $P/*.dsc.inc $P/*.fdf.inc 2>/dev/null | head -40
echo "== include files"
grep -n "!include" $P/*.dsc $P/*.fdf 2>/dev/null | head -20
