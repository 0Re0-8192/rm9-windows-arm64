#!/bin/bash
# logdump image for the FDT-scan experiment = production MuChain build + ONCEMODE + ONCE + FDTSCAN
set -e
W=<RM9_WORKDIR>/winboot
cp $W/muchain_esp.img /root/fdtscan_tmp.img
echo 1 > /root/once_flag.txt
for f in ONCEMODE.TXT ONCE.TXT FDTSCAN.TXT; do mcopy -i /root/fdtscan_tmp.img -o /root/once_flag.txt ::$f; done
cp /root/fdtscan_tmp.img $W/muchain_esp_fdtscan.img
cp $W/muchain_esp.img $W/muchain_esp_once_touch2.img
sha256sum $W/muchain_esp_fdtscan.img
