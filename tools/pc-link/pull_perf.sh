#!/bin/bash
P=<RM9_WORKDIR>/refs
V=/root/.venv/bin/python3
OUT=/root/diag_out
cd /root
rm -f $OUT/perf.txt
$V $P/ntfs_remote.py cat rm9/perf.txt $OUT/perf.txt >/dev/null 2>&1
echo "== perf.txt ($(stat -c %s $OUT/perf.txt 2>/dev/null || echo missing) bytes)"
# PowerShell Set-Content/Add-Content write ANSI by default on Windows PowerShell 5.1; try cp932, fall back to utf-16
if iconv -f utf-16le -t utf-8 $OUT/perf.txt 2>/dev/null | head -c 20 | grep -q perf; then iconv -f utf-16le -t utf-8 $OUT/perf.txt | tr -d '\r\0'; else iconv -f cp932 -t utf-8 -c $OUT/perf.txt | tr -d '\r\0'; fi
