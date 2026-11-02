#!/bin/bash
# make_once_img.sh - from the production logdump image (winboot/muchain_esp.img) build winboot/muchain_esp_once.img = the same + \ONCEMODE.TXT + \ONCE.TXT (slot-a launcher)
set -e
W=<RM9_WORKDIR>/winboot
cp $W/muchain_esp.img /root/once_tmp.img
echo 1 > /root/once_flag.txt
mcopy -i /root/once_tmp.img -o /root/once_flag.txt ::ONCEMODE.TXT
mcopy -i /root/once_tmp.img -o /root/once_flag.txt ::ONCE.TXT
mdir -i /root/once_tmp.img :: | grep -E "ONCE|LONGRUN|TOUCH|MUCHAIN|PCIE"
cp /root/once_tmp.img $W/muchain_esp_once.img
sha256sum $W/muchain_esp_once.img
