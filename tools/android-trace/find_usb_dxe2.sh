#!/bin/bash
cd /root/Mu-Silicium/Build/nx769jPkg
f=$(ls -d */FV 2>/dev/null | head -1); echo "FV dir: $f"
grep -i -n "usb" $f/FVMAIN.Fv.txt | head -40
echo "== dsc entries"
grep -n -i "usb" /root/Mu-Silicium/Platforms/ZTE/nx769jPkg/nx769j.dsc | head -30
echo "== inf of UsbfnDwc3Dxe"
cat /root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/UsbfnDwc3Dxe/UsbfnDwc3Dxe.inf | head -30
cat /root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/UsbfnDwc3Dxe/UsbfnDwc3Dxe.depex | xxd | head -3
echo "== protocols/strings in UsbfnDwc3Dxe.efi"
strings -n 6 /root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/UsbfnDwc3Dxe/UsbfnDwc3Dxe.efi | grep -i -E "usbfn|dwc3|vbus|cable|attach|chg|phy|typec|notify" | head -40
