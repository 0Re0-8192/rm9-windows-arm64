#!/bin/bash
cd /root/Mu-Silicium
echo "=== platform DXE.inc 36-72"; sed -n 36,72p Platforms/ZTE/nx769jPkg/Include/DXE.inc
echo "=== platform APRIORI.inc 18-52"; sed -n 18,52p Platforms/ZTE/nx769jPkg/Include/APRIORI.inc
echo "=== stock DXE.inc 30-50"; sed -n 30,50p Binaries/nx769j/DXE.inc
echo "=== PmicDxe inf"; ls Binaries/nx769j/QcomPkg/Drivers/PmicDxe; cat Binaries/nx769j/QcomPkg/Drivers/PmicDxe/*.inf | head -30
