#!/bin/bash
# Experimental Mu image WITHOUT the IPCC IRQ quarantine (PcdRamDebugQuarantineIpcc=FALSE) so that GlinkDxe/IPCCDxe can service ADSP doorbells once the ADSP runs.
# usage: build_ipcc.sh <image name>   (restores nx769j.dsc / .dsc.orig afterwards)
# NOTE: patch_stock_display.py (run by build_prod_display.sh) regenerates nx769j.dsc from nx769j.dsc.orig, so the PCD has to be changed in the .orig too.
set -e
P=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg
rm -f $P/nx769j.dsc.rm9pre_ipcc $P/nx769j.dsc.orig.rm9pre_ipcc
cp $P/nx769j.dsc $P/nx769j.dsc.rm9pre_ipcc
cp $P/nx769j.dsc.orig $P/nx769j.dsc.orig.rm9pre_ipcc
trap 'cp $P/nx769j.dsc.rm9pre_ipcc $P/nx769j.dsc; cp $P/nx769j.dsc.orig.rm9pre_ipcc $P/nx769j.dsc.orig' EXIT
sed -i 's/PcdRamDebugQuarantineIpcc|TRUE/PcdRamDebugQuarantineIpcc|FALSE/' $P/nx769j.dsc $P/nx769j.dsc.orig
grep -n "QuarantineIpcc" $P/nx769j.dsc $P/nx769j.dsc.orig
rm -rf /root/Mu-Silicium/Build/nx769jPkg/DEBUG_CLANGPDB/AARCH64/nx769jPkg/Drivers/RamDebugGuardDxe
bash <RM9_WORKDIR>/refs/build_prod_display.sh "$1"
grep "_PCD_VALUE_PcdRamDebugQuarantineIpcc" /root/Mu-Silicium/Build/nx769jPkg/DEBUG_CLANGPDB/AARCH64/nx769jPkg/Drivers/RamDebugGuardDxe/RamDebugGuardDxe/DEBUG/AutoGen.h
