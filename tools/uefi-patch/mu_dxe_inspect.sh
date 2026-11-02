#!/bin/bash
P=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg
echo "== Include/"; ls $P/Include
echo "== DXE.inc (usb / pwr / config related + count)"
wc -l $P/Include/DXE.inc
grep -n -i -E "usb|PwrCtrl|Charger|Pmic|TypeC|Ucsi|Tcpc" $P/Include/DXE.inc | head -30
echo "== APRIORI.inc"; grep -n -i usb $P/Include/APRIORI.inc | head
echo "== sample lines"; sed -n 1,12p $P/Include/DXE.inc
echo "== blobs available that look related"
ls /root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers | grep -i -E "usb|pwr|chg|charger|pmic|glink|typec|ucsi|tcpc|clock|ioexp|crm" 
