#!/bin/bash
# usage: ntfs_cat_many.sh <rel path on C:> ... ; prints the tail of each
cd /root
for f in "$@"; do
  echo "== $f"
  rm -f /root/_t.txt
  /root/.venv/bin/python3 <RM9_WORKDIR>/refs/ntfs_remote.py cat "$f" /root/_t.txt >/dev/null 2>&1
  [ -f /root/_t.txt ] && tail -c 1200 /root/_t.txt || echo "(not readable)"
  echo
done
