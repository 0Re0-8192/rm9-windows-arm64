#!/bin/bash
# make_menu_img.sh <out name> <A|W>  - production logdump image (winboot/muchain_esp.img) + MENU.TXT + NEXT.TXT (A = Android, W = Windows once) -> winboot/<out name>
set -e
W=<RM9_WORKDIR>/winboot
cp $W/muchain_esp.img /root/menu_tmp.img
echo 1 > /root/menu_flag.txt
printf '%s' "$2" > /root/next_flag.txt
mcopy -i /root/menu_tmp.img -o /root/menu_flag.txt ::MENU.TXT
mcopy -i /root/menu_tmp.img -o /root/next_flag.txt ::NEXT.TXT
cp /root/menu_tmp.img $W/$1
mdir -i $W/$1 :: | grep -E "MENU|NEXT|ONCE"
sha256sum $W/$1
