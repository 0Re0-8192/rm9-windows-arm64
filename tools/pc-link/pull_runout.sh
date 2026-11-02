#!/bin/bash
# pull C:\rm9\boot.txt and run_out.txt (+ optional extra names as args) from the phone and print them
P=<RM9_WORKDIR>/refs
V=/root/.venv/bin/python3
OUT=/root/diag_out
mkdir -p $OUT
cd /root
for f in boot.txt run_out.txt "$@"; do
  rm -f $OUT/$f
  $V $P/ntfs_remote.py cat rm9/$f $OUT/$f >/dev/null 2>&1
  echo "================ $f ($(stat -c %s $OUT/$f 2>/dev/null || echo missing) bytes)"
  [ -f $OUT/$f ] && iconv -f cp932 -t utf-8 -c $OUT/$f | tr -d '\r\0' | head -${LINES_MAX:-120}
done
