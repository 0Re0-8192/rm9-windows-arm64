#!/bin/bash
# usage: pull_files.sh <rm9-relative path> ...   prints each C:\rm9\<path> (utf-16/cp932 tolerant)
cd /root
for f in "$@"; do
  rm -f /root/pf.tmp
  /root/.venv/bin/python3 <RM9_WORKDIR>/refs/ntfs_remote.py cat "rm9/$f" /root/pf.tmp >/dev/null 2>&1
  echo "=== $f ($(stat -c %s /root/pf.tmp 2>/dev/null || echo missing) bytes)"
  [ -f /root/pf.tmp ] || continue
  if head -c 2 /root/pf.tmp | xxd -p | grep -q '^fffe'; then iconv -f utf-16 -t utf-8 /root/pf.tmp | tr -d '\r'; else iconv -f cp932 -t utf-8 -c /root/pf.tmp | tr -d '\r\0'; fi | head -${LINES_MAX:-25}
done
