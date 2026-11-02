#!/bin/bash
# which USB related drivers does the nx769j Mu build carry (blobs from the stock UEFI)?
B=/root/Mu-Silicium/Binaries/nx769j
echo "== blobs"; find $B -iname "*usb*" 2>/dev/null | head -30
echo "== dsc / fdf references"
grep -rn -i "usbfn\|UsbConfig\|UsbDevice\|Dwc3" /root/Mu-Silicium/Platforms/ZTE/nx769jPkg/*.dsc /root/Mu-Silicium/Platforms/ZTE/nx769jPkg/*.fdf 2>/dev/null | head -20
echo "== which of them are in the built image's FV (names)"
ls /root/Mu-Silicium/Build/nx769jPkg/*/FV 2>/dev/null | head
