#!/bin/bash
# Experimental Mu image with Qualcomm's UsbDeviceDxe enabled (EFI_USB_DEVICE_PROTOCOL) so that MuChain can start a USB device towards the PC.
# usage: build_usbdev.sh <image name>      (restores DXE.inc afterwards; the normal prod image is unaffected)
set -e
P=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Include
cp $P/DXE.inc $P/DXE.inc.rm9pre_usbdev
trap 'cp $P/DXE.inc.rm9pre_usbdev $P/DXE.inc' EXIT
sed -i 's|^#   INF Binaries/nx769j/QcomPkg/Drivers/UsbDeviceDxe/UsbDeviceDxe.inf|  INF Binaries/nx769j/QcomPkg/Drivers/UsbDeviceDxe/UsbDeviceDxe.inf|' $P/DXE.inc
grep -n "UsbDeviceDxe" $P/DXE.inc
bash <RM9_WORKDIR>/refs/build_prod_display.sh "$1"
