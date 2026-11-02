#!/bin/bash
# pull everything the USB test logged (C:\rm9\session\*, run_out.txt, boot.txt) into winboot/usbtest_<stamp>/ and show a short summary
V=/root/.venv/bin/python3
N=<RM9_WORKDIR>/refs/ntfs_remote.py
OUT=<RM9_WORKDIR>/winboot/usbtest_$(date +%Y%m%d_%H%M)
mkdir -p $OUT; cd /root
for f in session/alive.txt session/temps.txt session/changes.txt session/users.txt session/shots.txt session/usb.etl session/System.evtx session/setupapi.dev.log session/shot_0.png session/shot_1.png session/shot_2.png session/shot_3.png session/shot_4.png session/shot_5.png run_out.txt boot.txt; do
  $V $N cat rm9/$f $OUT/$(basename $f) >/dev/null 2>&1
done
ls -la $OUT
echo "--- alive (first/last)"; head -1 $OUT/alive.txt | tr -d '\0\r'; tail -2 $OUT/alive.txt | tr -d '\0\r'
echo "--- changes (change headers)"; (iconv -f utf-16 -t utf-8 $OUT/changes.txt 2>/dev/null || cat $OUT/changes.txt) | tr -d '\r\0' | grep -E "^--- |^volume|^Disk|USB \|" | tail -40
echo "$OUT"
