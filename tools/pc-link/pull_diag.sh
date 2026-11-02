#!/bin/bash
# copy the diagnostics Windows wrote on the phone into /root/diag_out and show the summary
P=<RM9_WORKDIR>/refs
V=/root/.venv/bin/python3
OUT=/root/diag_out
mkdir -p $OUT
cd /root
for f in diag.txt w1.txt diag_devices.txt diag_drivers.csv ev_system.txt ev_app.txt; do
  $V $P/ntfs_remote.py cat rm9/$f $OUT/$f >/dev/null 2>&1 && echo "pulled $f ($(stat -c %s $OUT/$f) bytes)"
done
echo "================ diag.txt"
iconv -f utf-16le -t utf-8 $OUT/diag.txt 2>/dev/null | head -80 || cat $OUT/diag.txt | head -80
