#!/bin/bash
# Experimental Mu image that also loads Qualcomm's PmicDxe (PmicSchg/PmicVersion/PmicGpio... protocols; it is NOT in the normal FDF) so that UsbPwrCtrlDxe / UsbConfigDxe can initialise.
# usage: build_pmic.sh <image name>      (restores DXE.inc / APRIORI.inc afterwards)
set -e
P=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Include
cp $P/DXE.inc $P/DXE.inc.rm9pre_pmic; cp $P/APRIORI.inc $P/APRIORI.inc.rm9pre_pmic
trap 'cp $P/DXE.inc.rm9pre_pmic $P/DXE.inc; cp $P/APRIORI.inc.rm9pre_pmic $P/APRIORI.inc' EXIT
sed -i 's|^  INF Binaries/nx769j/QcomPkg/Drivers/SPMIDxe/SPMIDxe.inf|&\n  INF Binaries/nx769j/QcomPkg/Drivers/PmicDxe/PmicDxeLa.inf|' $P/DXE.inc
sed -i 's|^  INF Binaries/nx769j/QcomPkg/Drivers/PmicGlinkDxe/PmicGlinkDxe.inf|  INF Binaries/nx769j/QcomPkg/Drivers/PmicDxe/PmicDxeLa.inf\n&|' $P/APRIORI.inc
grep -n "PmicDxe" $P/DXE.inc $P/APRIORI.inc
bash <RM9_WORKDIR>/refs/build_prod_display.sh "$1"
