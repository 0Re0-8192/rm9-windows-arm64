#!/bin/bash
# usage: pull_session_files.sh <dest dir (windows path under /mnt/d)> <file...>   pulls C:\rm9\session\<file> into the destination
D=$1; shift
mkdir -p "$D"; cd /root
for f in "$@"; do
  /root/.venv/bin/python3 <RM9_WORKDIR>/refs/ntfs_remote.py cat "rm9/session/$f" "$D/$f" >/dev/null 2>&1
  echo "$f: $(stat -c %s "$D/$f" 2>/dev/null || echo missing)"
done
