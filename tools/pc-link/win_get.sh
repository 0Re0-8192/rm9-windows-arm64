#!/bin/bash
# copy files from the phone's windows partition to the PC (read-only):  win_get.sh <outdir> <path> ...
OUT=$1; shift
mkdir -p "$OUT"
cd <RM9_WORKDIR>/refs
for p in "$@"; do
  b=$(basename "$p")
  /root/.venv/bin/python3 ntfs_remote.py cat "$p" > "$OUT/$b" 2>/dev/null
  echo "$b $(stat -c %s "$OUT/$b")"
done
