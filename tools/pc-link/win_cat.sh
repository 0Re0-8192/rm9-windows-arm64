#!/bin/bash
# print files from the phone's windows partition (read-only, Android up):  win_cat.sh <path> ...
cd <RM9_WORKDIR>/refs
for p in "$@"; do echo "=== $p"; /root/.venv/bin/python3 ntfs_remote.py cat "$p" 2>&1 | tail -${TAILN:-15} | cut -c1-200; done
