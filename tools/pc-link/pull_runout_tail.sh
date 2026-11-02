#!/bin/bash
# latest run's output only: print C:\rm9\run_out.txt from the LAST "==== ... start" marker (arg1 = marker regex, default "thermal test start")
P=<RM9_WORKDIR>/refs
V=/root/.venv/bin/python3
OUT=/root/diag_out
mkdir -p $OUT; cd /root
rm -f $OUT/run_out.txt
$V $P/ntfs_remote.py cat rm9/run_out.txt $OUT/run_out.txt >/dev/null 2>&1
M="${1:-thermal test start}"
iconv -f cp932 -t utf-8 -c $OUT/run_out.txt | tr -d '\r\0' | awk -v m="$M" '{a[NR]=$0; if ($0 ~ m) s=NR} END{for(i=s;i<=NR;i++) print a[i]}' | grep -v '^$' | head -${LINES_MAX:-80}
