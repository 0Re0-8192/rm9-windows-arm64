#!/bin/bash
# make_flag_img.sh <out name> <FLAG.TXT>...  - production logdump image (winboot/muchain_esp.img) + ONCEMODE.TXT + ONCE.TXT + the given extra flag files -> winboot/<out name>
set -e
W=<RM9_WORKDIR>/winboot
OUT=$1; shift
cp $W/muchain_esp.img /root/flag_tmp.img
echo 1 > /root/once_flag.txt
for f in ONCEMODE.TXT ONCE.TXT "$@"; do mcopy -i /root/flag_tmp.img -o /root/once_flag.txt ::$f; done
cp /root/flag_tmp.img $W/$OUT
mdir -i $W/$OUT :: | grep -E "ONCE|ANDR|ANDJ|FDTS"
sha256sum $W/$OUT
